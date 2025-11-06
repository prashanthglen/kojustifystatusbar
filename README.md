# Justify KOReader Status bar

This is my attempt to distribute all the items in the KOReader status bar to be spread apart across the width of the device and be equally spaced.

## Patch
To illustrate the end look that I want to achieve, I have a patch here where the user can define what items they want to see on the status bar. Things I still want to add on to the patch:

- [ ] Progress bar.
- [ ] Select items to display from the settings (for footer only).
- [ ] Implement more than 3 dynamic spaces.

## Usage
1. Download the ![file](./2-justified-footer.lua).
2. Modify the contents of `footer_right_text`, `footer_center_text` and `footer_left_text` to entries of your choice.
3. Move this patch over to the `koreader/patches` folder.
4. Restart KOReader.
