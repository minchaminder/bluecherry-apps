#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("server/media_writer.cpp")
RULES = Path("debian/rules")
CONTROL = Path("debian/control.in")


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Cannot apply {description}: expected exactly one source block, found {count}"
        )
    return text.replace(old, new, 1)


text = SOURCE.read_text(encoding="utf-8")

old_validation = """	int channels = audio_props.channels;
	int sample_rate = audio_props.sample_rate;
	
	// Enhanced problematic audio detection - discard completely if issues detected
	if ((codec_id == AV_CODEC_ID_PCM_MULAW || codec_id == AV_CODEC_ID_PCM_ALAW) && channels == 1) {
		bc_log(Warning, \"Discarding problematic audio stream: %s with 1 channel (causes muxer initialization failure)\", 
			avcodec_get_name(codec_id));
		return false;
	}
	
	// Check for non-standard sample rates for G711 codecs
"""

new_validation = """	int sample_rate = audio_props.sample_rate;

	/* Mono G.711 is valid and common in surveillance devices. The previous
	 * rejection confused a container limitation with an invalid stream.
	 * media_writer::open() selects the MOV muxer for PCMA/PCMU below. */

	// Check for non-standard sample rates for G711 codecs
"""

text = replace_once(
    text,
    old_validation,
    new_validation,
    "mono G.711 validation change",
)

old_muxer = """	/* Get the output format */
	const AVOutputFormat *fmt_out = av_guess_format(\"mp4\", NULL, \"video/mp4\");
	if (fmt_out == NULL)
	{
		bc_log(Error, \"media_writer: MP4 output format is not found!\");
		errno = EINVAL;

		close();
		return -1;
	}
"""

new_muxer = """	/* MP4 does not accept stream-copied PCMA/PCMU, while the QuickTime MOV
	 * muxer supports the alaw/ulaw sample entries. Keep both video and audio
	 * packet-copy and change only the container mode for G.711 recordings. */
	const bool use_mov_for_g711 = properties.has_audio() &&
		(properties.audio.codec_id == AV_CODEC_ID_PCM_ALAW ||
		 properties.audio.codec_id == AV_CODEC_ID_PCM_MULAW);
	const char *format_name = use_mov_for_g711 ? \"mov\" : \"mp4\";
	const char *mime_type = use_mov_for_g711 ? \"video/quicktime\" : \"video/mp4\";

	if (use_mov_for_g711) {
		bc_log(Info, \"Using QuickTime MOV muxer for %s audio in recording %s\",
			avcodec_get_name(properties.audio.codec_id), path.c_str());
	}

	const AVOutputFormat *fmt_out = av_guess_format(format_name, NULL, mime_type);
	if (fmt_out == NULL)
	{
		bc_log(Error, \"media_writer: %s output format is not found!\", format_name);
		errno = EINVAL;

		close();
		return -1;
	}
"""

text = replace_once(text, old_muxer, new_muxer, "G.711 muxer selection")
SOURCE.write_text(text, encoding="utf-8")

rules = RULES.read_text(encoding="utf-8")
rules = replace_once(
    rules,
    "#!/usr/bin/make -f\n\n",
    "#!/usr/bin/make -f\n\n"
    "# Bluecherry's top-level Makefile does not express dependencies between\n"
    "# misc libraries, libbluecherry, utilities and bc-server. Build serially.\n"
    "export DEB_BUILD_OPTIONS := $(filter-out parallel=%,$(DEB_BUILD_OPTIONS)) parallel=1\n\n",
    "serial Debian build setting",
)
RULES.write_text(rules, encoding="utf-8")

control = CONTROL.read_text(encoding="utf-8")
control = replace_once(
    control,
    " libidn11-dev, libbsd-dev, yasm, libudev-dev, libopencv-dev,\n",
    " libmariadb-dev-compat, libidn11-dev, libbsd-dev, yasm, libudev-dev, libopencv-dev,\n",
    "MariaDB compatibility build dependency",
)
CONTROL.write_text(control, encoding="utf-8")

print(
    "Applied Bluecherry G.711 recording hotfix, serial build setting, "
    "and Ubuntu 24.04 MariaDB compatibility dependency"
)
