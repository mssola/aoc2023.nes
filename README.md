[Advent of Code 2023](https://adventofcode.com/2023) on the NES, baby! (let's
see if I actually finish it...)

Each day is written into its own file inside of `src`. Build everything by just
calling `make` and you will get a `.nes` file per day inside of the `out`
directory. Before doing that, though, you will need a compiler for the 6052
platform. A good option is [cc65](https://github.com/cc65/cc65), which is
available on all major platforms. Otherwise, if you want to use another
compiler, you can pass the `CC65` and `CCOPTS` variables to the Makefile.

After that, it's recommended that you run the ROMs with an emulator with
debugging support or at least some form of memory visualization. This is because
some days have nothing to show for other than updating some values on the NES
memory. A safe bet is to go with either [fceux](https://fceux.com/web/home.html)
or [Mesen](https://github.com/SourMesen/Mesen2/), which provide tools like RAM
watchers or a full debugger. Otherwise, you can run tests with `make test`, but
for now this requires a screen. Thus, we cannot run it on a CI, for now. This is
mainly used so to ensure that changes on shared code don't mess with the end
result from exercises.

Notice also that I will use some terms without actually introducing them. That
is, I expect you to go over the [NES Dev
wiki](https://www.nesdev.org/wiki/Nesdev_Wiki) for glossary or for full
documentation on the stuff being shown here. That is, if you find that on a
bunch of comments I write stuff like "memory mapper", "MMC3 chip", "OAM" or
stuff like that, just go to the [NES Dev
wiki](https://www.nesdev.org/wiki/Nesdev_Wiki) to get a better picture.

## License

Released under the [GPLv3+](http://www.gnu.org/licenses/gpl-3.0.txt), Copyright
(C) 2023-<i>Ω</i> Miquel Sabaté Solà.

All code under the `vendor` directory is directly taken from other people and
not written by me. Attribution is done inside of each file.
