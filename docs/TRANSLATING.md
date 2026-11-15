# Translating NeoFreeBird

Thank you for helping with translating NeoFreeBird! 

## Supported Languages

NeoFreeBird currently supports these (non-English) languages (although more can be added with a PR)
- Arabic
- German
- Spanish
- French
- Croatian
- Indonesian
- Japanese
- Korean
- Polish
- Russian
- Swedish
- Turkish
- Ukrainian
- Chinese Simplified
- Chinese Traditional

## Requirements
- Fluent knowledge in any of these languages and English
- Some sort of text editor
- Git on your computer
- A GitHub account
- (Optional but very helpful) [Python 3](https://www.python.org) installed, this will run the check_localization.py file and help you find missing text

## Translating Text
1. Fork this NeoFreeBird repo and clone your fork to your computer.
2. **Get a list of all missing text in your language.** You can do this manually (if you've already seen untranslated text in the app), or use the check_localization.py file. To use that file, clone the repo somewhere on your computer, enter a terminal into the root folder of NeoFreeBird, and (with Python installed), run `./check_localization.py`. It will give you more details on how to use the program to find missing text. For example, here is me running `./check_localization.py tr`
```
   tr — 248/278 translated (89.2%)
  missing (30):
    OK_ACTION_LABEL
    NO_FOCUS_LOST_TITLE
    NO_FOCUS_LOST_DETAIL
    USE_TENOR_GIFS_TITLE
    USE_TENOR_GIFS_DETAIL
    DOWNLOAD_HIGHEST_QUALITY_TITLE
    DOWNLOAD_HIGHEST_QUALITY_DETAIL
    COPY_PROFILE_INFO_MENU_OPTION_7
    COPY_PROFILE_INFO_MENU_OPTION_8
    PHONE_OR_EMAIL_OR_USERNAME_LABEL
    PASSWORD_LABEL
    LOG_IN_ACTION_LABEL
    LOG_IN_TITLE
    DOWNLOAD_ACTIVITY_VIEW_LABEL
    DOWNLOAD_LIVE_ACTIVITY_DOWNLOADING
    SETTINGS_EXPORT_TITLE
    SETTINGS_IMPORT_TITLE
    SETTINGS_EXPORT_FAILED_TITLE
    SETTINGS_EXPORT_WRITE_FAILED
    SETTINGS_IMPORT_CONFIRM_TITLE
    SETTINGS_IMPORT_CONFIRM_MESSAGE
    SETTINGS_IMPORT_CONFIRM_BUTTON
    SETTINGS_IMPORT_FAILED_TITLE
    SETTINGS_IMPORT_SUCCESS_TITLE
    SETTINGS_IMPORT_SUCCESS_MESSAGE
    SETTINGS_IMPORT_RESTART_BUTTON
    SETTINGS_IMPORT_LATER_BUTTON
    SETTINGS_TRANSFER_UNREADABLE_FILE
    SETTINGS_TRANSFER_MALFORMED_FILE
    SETTINGS_TRANSFER_NO_SETTINGS
  not in en (stale?) (2):
    SHARING_DOMAIN_DETAIL
    TAB_CUSTOMIZATION_TITLE
```

3. **Fill out the translations.** The file for your language will be found in `layout/Library/Application Support/BHT/BHTwitter.bundle/xx.lproj/Localizable.strings` (where xx is the 2 letter code for your language). Make sure to keep the general flow and meaning of the phrase similar to that of English. If you're unsure on what a feature does or what it's trying to say, feel free to ping me on Twitter (@orionblur) or make an issue! Each line should only have 1 translation, and a translation key and value should be covered in quotes. There should also be a semicolon at the end of the line. Here's what that looks like in practice:
```
"NEW_OPTION_TITLE" = "Some text here";
"NEW_OPTION_DETAIL" = "More text here";
```
4. **Commit and push your changes to your fork.** Make sure that everything looks good before making a PR.
5. **Make a PR to this repo **(go to the [Pull Requests](https://github.com/NeoFreeBird/app/pulls) tab, click on "New Pull Request", and have the base repository be orionblur's, with the head repo being yours.
6. I will go through the PR and merge it as soon as I can get to it. It'll be very helpful if you can compile the app (either locally or through Github Actions) and show that your new translations are taking shape (although this is purely optional!).

That's it! If you have any questions on translations, please feel free to ping me or make an issue, and I'll do my best to help.

## Renaming Terminology
This is slightly different, since instead of modifying an existing file (if it doesn't exist already), you'll need to make a new file called RenameWords.strings. NeoFreeBird is programmed to read this file to replace text within the app. For example, here's how it looks like in English:

```
/*NEW WORDS |  OLD WORDS */
"repost" = "retweet";
"reposts" = "retweets";
"reposted" = "retweeted";
"reposting" = "retweeting";
"post" = "Tweet";
"posts" = "Tweets";
"posted" = "Tweeted";
"posting" = "Tweeting";
"premium" = "blue";
"X" = "Twitter";
```

The left side contains the new terminology the X app uses, while the right side uses terminology the old Twitter app used. Since the words differ between languages, make sure to double check before adding to this file. Once you're done, you can go through the same flow as committing and making a PR as with the normal strings.


### Grammar and context

Renaming uses three layers, in this order:

1. `RenameOverrides.strings`: the app's localization key mapped to a complete
   replacement. Use this when the same text has different meanings in different
   UI contexts. Preserve all format placeholders and their argument positions.
2. `RenamePhrases.strings`: exact, case-sensitive source text mapped to a complete
   replacement. This also works for server-composed text without a localization
   key. Include each actual spelling explicitly; phrases are not fragments or
   format patterns. An identity entry prevents generic replacements for that text.
3. `RenameWords.strings`: terminology fragments that remain correct in context.
   Longer matches win. Lowercase entries support original, initial-capital and
   all-capital forms using locale-aware casing (including Turkish dotted I).
   Uppercase-bearing keys such as `X` require an exact match. Japanese and Chinese
   terms can match next to other characters without spaces.

Do not translate grammar by swapping a noun stem or a general verb everywhere.
List inflected forms and preposition phrases explicitly (see Polish `we wpisie`),
which lets the replacement change the whole construction. Use full phrases or
localization keys for gender agreement, word order, and ambiguous actions like
“publish” or “quote”. Unknown inflections stay unchanged. Keep replacements stable
when processed twice. Missing tables never fall back to another language.

Run the Foundation regression checks on macOS from the repository root:

```sh
xcrun clang -fobjc-arc -framework Foundation -Isrc src/Core/BHTTerminology.m tests/TerminologyTests.m -o /tmp/nfb-terminology-tests
/tmp/nfb-terminology-tests
```
