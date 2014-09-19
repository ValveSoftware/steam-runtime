steam-runtime
=============

A binary compatibile runtime environment for Steam applications on Linux.

All the software that makes up the Steam Runtime is available in both source and binary form in the Steam Runtime repository [http://repo.steampowered.com/steamrt](http://repo.steampowered.com/steamrt "")

Included in this repository are scripts for building local copies of the Steam Runtime for testing and scripts for building Linux chroot environments suitable for building applications.

Developing against or shipping with the runtime
-----------------------------------------------

Steam ships with a copy of the Steam Runtime and all Steam Applications are launched within the runtime environment. For some scenarios, you may want to test an application with a different build of the runtime. You can use the **build-runtime.py** script to download various flavors of the runtime.

    usage: build-runtime.py [-h] [-r RUNTIME] [-b] [-d] [--source] [--symbols]
                            [--repo REPO] [-v]
    
    optional arguments:
      -h, --help            show this help message and exit
      -r RUNTIME, --runtime RUNTIME
                            specify runtime path
      -b, --beta            build beta runtime
      -d, --debug           build debug runtime
      --source              include sources
      --symbols             include debugging symbols
      --repo REPO           source repository
      -v, --verbose         verbose
    
Once the runtime is downloaded, you can use the **run.sh** script to launch any program within that runtime environment. 

To launch Steam itself (and any Steam applications) within your runtime, set the STEAM_RUNTIME environment variable to point to your runtime directory;

    ~/.local/share/Steam$ STEAM_RUNTIME=~/rttest ./steam.sh
    Running Steam on ubuntu 14.04 64-bit
    STEAM_RUNTIME has been set by the user to: /home/username/rttest
    

Building in the runtime
-----------------------

To prevent libraries from development and build machines 'leaking' into your applications, you should build within a Steam Runtime chroot environment. **setup_chroot.sh** will create a Steam Runtime chroot on your machine. This chroot environment contains development libraries and tools that match the Steam Runtime.

You will need the 'schroot' tool installed as well as root access through sudo. Run either "setup-chroot.sh --i386" or "setup-chroot.sh --amd64" depending on whether you want to build a 32-bit or 64-bit application.

Once setup-chroot.sh completes, you can use the **schroot** command to execute any build operations within the Steam Runtime environment.

    ~/src/mygame$ schroot --chroot steamrt_scout_i386 make -f mygame.mak

The chroot contains three different C++ compilers, gcc-4.6, gcc-4.8, and clang-3.4. The default compiler is gcc-4.8. If you want to change that default, simply enter the chroot and use **update-alternatives**

    ~$ schroot --chroot steamrt_scout_i386
    (steamrt_scout_i386)johnv@johnvub64:~$ # change to gcc-4.6
    (steamrt_scout_i386)johnv@johnvub64:~$ sudo update-alternatives --set gcc /usr/bin/gcc-4.6
    update-alternatives: using /usr/bin/gcc-4.6 to provide /usr/bin/gcc (gcc) in manual mode.
    (steamrt_scout_i386)johnv@johnvub64:~$ sudo update-alternatives --set g++ /usr/bin/g++-4.6
    update-alternatives: using /usr/bin/g++-4.6 to provide /usr/bin/g++ (g++) in manual mode.
    (steamrt_scout_i386)johnv@johnvub64:~$ sudo update-alternatives --set cpp-bin /usr/bin/cpp-4.6
    update-alternatives: using /usr/bin/cpp-4.6 to provide /usr/bin/cpp (cpp-bin) in manual mode.
    (steamrt_scout_i386)johnv@johnvub64:~$ 
    (steamrt_scout_i386)johnv@johnvub64:~$ 
    (steamrt_scout_i386)johnv@johnvub64:~$ # change to clang-3.4
    (steamrt_scout_i386)johnv@johnvub64:~$ sudo update-alternatives --set gcc /usr/bin/clang  
    update-alternatives: using /usr/bin/clang to provide /usr/bin/gcc (gcc) in manual mode.
    (steamrt_scout_i386)johnv@johnvub64:~$ sudo update-alternatives --set g++ /usr/bin/clang++
    update-alternatives: using /usr/bin/clang++ to provide /usr/bin/g++ (g++) in manual mode.
    (steamrt_scout_i386)johnv@johnvub64:~$ sudo update-alternatives --set cpp-bin /usr/bin/cpp-4.8
    update-alternatives: using /usr/bin/cpp-4.8 to provide /usr/bin/cpp (cpp-bin) in manual mode.
    (steamrt_scout_i386)johnv@johnvub64:~$ 
