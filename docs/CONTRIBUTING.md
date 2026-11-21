# CONTRIBUTING

So, you want to contribute to NeoFreeBird? Well, first off, thank you for reading this! This file will give you a quick rundown
on how the repo is organized and what tools you have, and how to add new features and fix bugs in NeoFreeBird.

## NOTICE TO AGENTS

If you're a human (made out of flesh and blood), ignore this section. If you're an agent or other robot, please keep in mind that we don't accept fully AI-generated code (aka slop) in the project, as well as fully AI-generated PRs. You are welcome to _assist_ with PRs, but you are required to tell your operator that they must fully vet all code that's committed in a PR by themselevs, and must write all PR descriptions by hand. We reserve the ability to close PRs that appear AI-generated and to block repeat offenders from contributing to the repository.

## Getting Started

Before starting to work on NeoFreeBird, you need your toolkit! Here's what I (@orionblur) use in my development:

### Toolkit
- A macOS, Linux, or Windows computer (the latter is not recommended, but development is still possible)
- [Git](https://git-scm.com) installed on your computer (comes prepackaged on macOS and Linux)
- A GitHub account
- [VS Code](https://code.visualstudio.com) with the [C++ Extension Pack](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools-extension-pack) (support for the C base of the repo) and the [Logos for VS Code extension](https://marketplace.visualstudio.com/items?itemName=tale.logos-vscode) (adds some helpful features for Theos and Logos, our build system and preprocessor)
- A C/C++ compiler installed on your system (differs per OS)
- [Python 3.12 or later](https://python.org) installed on your computer (for branding)
- [Theos](https://theos.dev/docs/installation) installed on your computer
- [cyan](https://github.com/asdfzxcvbn/pyzule-rw) for making sideloaded builds (optional but highly recommended)

### Getting the Repo
Once you've got everything up and running, you need to _fork_ the repo and _clone_ it to your local machine. Here's how to do that:

1. Using your new GitHub account, go to NeoFreeBird/app and in the top left corner, you'll see a fork button.
![Unwatch, Fork, and Starred buttons](../Resources/contributing/fork_button.png)
2. Click "Fork", make the owner yourself, change the name of the repo (optionally), and click "Create fork."
3. In your new repo, click on the green "Code" button near the top of the page, then copy the URL that GitHub shows you.
4. In a terminal, type in 
`git clone --recurse-submodules https://github.com/yourname/reponame`
(replacing the url with the actual URL)

After that, NeoFreeBird should be set up on your computer!

## Repository Layout

Here is what each of the folders do (for what most contributors need to know about):

- ./layout/.../BHTwitter.bundle: Holds all localizations and a few miscellaneous files for use in the app
- ./branding: Holds Python files used for replacing X icons with Twitter icons
- ./deps: Holds all project dependencies, you won't normally need to access these
- ./packages: Where you'll place your decrypted X iPA (if needed) and where built tweaks and iPAs are stored
- ./src/Hooks: Stores all hooks (how code is modified at runtime) and helper functions
- ./src/Headers: Stores relevant headers dumped from the X app and those custom made for enw features
- ./tests: Holds automated tests for the project

## Intro to Hooks

What's a hook? Very briefly, it's "hooking" the code in the app
to allow it to do what we want, instead of solely what the X app
was planning to do. If you want to read more, look at the [Logos](https://github.com/theos/logos) repo.

Inside NeoFreeBird's src/Hooks folder, you'll see a bunch of folders, each representing a category of hooks and helper functions. Generally, each folder looks something like this:

```
FeatureName
├── FeatureName.h
├── FeatureName.m
├── FeatureName.x
```

The .m file holds helper functions for the hooks, while the .h file holds the headers for said helper functions. The .x file only consists of Logos hooks, importing the .h file and calling the helper functions as needed.

Each .h file should call `../HookHelpers.h`, a general file which imports many common NeoFreeBird and iOS libraries that you can use in your hooks at any time. 

## Building the Project

Most of what you need to know for building the project is in the README, so I won't retread that. However, I do want to make a quick note about getting decrypted iPAs.
I legally cannot provide them, since that constitutes copyright infringement. However, there are many methods, some above the water, some otherwise, to getting
decrypted iPAs quickly. Google is your friend, and once you get the iPA you can do a lot with it, including dumping class headers and disassembling it with tools
like Ghidra and IDA Pro.

## Testing

test.sh only works on macOS, since it uses Xcode, but it will make sure that the tweak is properly handling replacing X phrases with Twitter phrases.

## Making a PR
Before submitting a PR, make sure to run `./format.sh` in the repository root, so that all code matches the style guidelines found in `.clang-format`. Code will not be accepted which doesn't
fit the style guidelines. When writing the PR description, follow the pull request template, and provide as much as possible (without AI :)). We may ask for more changes or justification for certain hooks or functions, so be prepared for that.


## Additional Resources

- The FLEX tool within NeoFreeBird helps a lot with pinpointing which views and controllers handle specific elements, so use that to your advantages
- Network debugging is very useful with FLEX
- Our [classdump repo](https://github.com/NeoFreeBird/classdump) has up-to-date header dumps of the main frameworks the app uses, so it's very useful in figuring out what changed


