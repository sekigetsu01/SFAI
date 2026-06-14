# Sekigetsu's Fedora Setup

## Installation:

On an Fedora installation as root, run the following:

```
git clone https://github.com/sekigetsu01/SFAI.git
cd SFAI/static
sh sfai.sh
```

## What is SFAI?

SFAI is a script that autoinstalls and autoconfigures my fedora system
system.

It can be run on a fresh install of Fedora and provides you
with an almost fully configured system. It has most of the
necessary software installed, but is primarily used for me to clean PDFs
with dangerzone and sync them between devices.


## Customization

By default, SFAI uses the programs [here in progs.csv](static/progs.csv) and installs
[my dotfiles repo here](https://github.com/sekigetsu01/fedora-dotfiles),

### The `progs.csv` list

SFAI will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`.

The first column is a "tag" that determines how the program is installed, ""
(blank) for the main repository, `F` to install a flatpak, `A` for instllation
via the AUR, `P` to install via pipx or `G` if the program is a
git repository that is meant to be `make && sudo make install`ed.

The second column is the name of the program in the repository, or the link to
the git repository, and the third column is a description (should be a verb
phrase) that describes the program. During installation, SFAI will print out
this information in a grammatical sentence. It also doubles as documentation
for people who read the CSV and want to install my dotfiles manually.

Depending on your own build, you may want to tactically order the programs in
your programs file. SFAI will install from the top to the bottom.

If you include commas in your program descriptions, be sure to include double
quotes around the whole description to ensure correct parsing.
