# PDF report font asset

`seeray-reports-cjk.ttf` is a static regular-weight subset of [Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc), distributed under the SIL Open Font License in `NOTO-CJK-OFL.txt`. It was subset for report labels, common Simplified Chinese, GB2312 characters, and common CJK punctuation; its family name was changed to `SeeRay Reports` because the source license reserves the name `Source`.

`seeray-reports-cjk-codepoints.txt` is the sorted codepoint-range map for that exact font. PDF export replaces unsupported glyphs with `?` rather than drawing a broken box. CSV and JSON exports are not modified.
