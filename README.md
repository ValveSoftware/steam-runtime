# Steam Runtime SDK

A binary compatible runtime environment for Steam applications on Linux.

## Introduction

The Linux version of Steam runs on many Linux distributions, ranging from the latest rolling-release distributions like Arch Linux to older LTS distributions like Ubuntu 14.04. To achieve this, it uses a special library stack, the *Steam Runtime*, which is installed in `~/.steam/root/ubuntu12_32/steam-runtime`. This is Steam Runtime version 1, codenamed `scout` after the Team Fortress 2 character class.

The Steam client itself is run in an environment that adds the shared libraries from Steam Runtime 1 'scout' to the library loading path, using the `LD_LIBRARY_PATH` environment variable. This is referred to as the [`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime]. Most native Linux games available through Steam are also run in this environment.

A newer approach to cross-distribution compatibility is to use Linux namespace (container) technology, to run games in a more predictable environment, even when running on an arbitrary Linux distribution which might be old, new, or unusually set up. This is implemented as a series of Steam Play compatibility tools and is referred to as the Steam [container runtime][container runtime] or the *Steam Linux Runtime*.

The Steam Runtime is also used by the [Proton][Proton] Steam Play compatibility tools, which run Windows games on Linux systems. Older versions of Proton (5.0 or earlier) use the same 'scout' [`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime] as most native Linux games. Newer versions of Proton (5.13 or newer) use a [container runtime][container runtime] with newer library versions: this is Steam Runtime version 2, codenamed 'soldier'.

More information about the [`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime] and [container runtime][container runtime] is available as part of the [steam-runtime-tools documentation][steam-runtime-tools documentation].

## Why Use Steam Runtime SDK?

- Ensures your application finds the correct libraries for smooth operation on different Linux systems.
- Prevents conflicts between development libraries on your machine and the libraries your application needs.

## Detailed Installation Instructions

### Prerequisites

Before you begin, ensure you have the following installed on your system:

- **Podman or Docker**: Choose one of these container tools. Installation instructions for both can be found here:
  - [Install Podman](https://podman.io/getting-started/installation)
  - [Install Docker](https://docs.docker.com/get-docker/)

- **Basic Command Line Knowledge**: Familiarity with terminal commands will help you navigate the installation process.

### Step-by-Step Installation

1. **Install Podman or Docker** (if not already installed):

   For **Ubuntu/Debian**:

   ```bash
   sudo apt update
   sudo apt install podman
    ```

## or for Docker:

```bash
sudo apt update
sudo apt install docker.io
```
## Download the SDK:


## Depending on the container tool you chose, run one of the following commands:

## For Podman:

```bash
podman pull registry.gitlab.steamos.cloud/steamrt/scout/sdk
```
## For Docker:

```bash
sudo docker pull registry.gitlab.steamos.cloud/steamrt/scout/sdk
```
## Create a Container Environment:

Once the download is complete, create a new container environment by running:

## For Podman:

```bash
podman run -it --rm --name steamrt-sdk registry.gitlab.steamos.cloud/steamrt/scout/sdk /bin/bash
```

## For Docker:

```bash
sudo docker run -it --rm --name steamrt-sdk registry.gitlab.steamos.cloud/steamrt/scout/sdk /bin/bash
```
## (Optional) Chroot Environment:

If you prefer a chroot environment, download the appropriate image from the Steam Runtime repository: Steam Runtime Repository. Follow the instructions provided with the downloaded image to set up the chroot.

## Common Troubleshooting Tips
Permission Denied Errors: If you encounter permission issues, ensure that you are running the commands with the correct privileges (e.g., using sudo for Docker).

Container Fails to Start: If the container fails to start, check your installation of Podman or Docker. Verify that it’s running correctly by checking the service status:

### For Docker:

```bash
sudo systemctl status docker
```

For Podman:

```bash
systemctl --user status podman
```

## Outdated Libraries: Ensure your system packages are up to date. Run:

```bash
sudo apt update
sudo apt upgrade
```
### Further Resources
For more detailed information on using the Steam Runtime SDK, refer to the official documentation.

If you run into issues, check the steam-runtime issue tracker for potential solutions or report a new issue.

### Additional Information
Debugging: If you need to use debugging tools like gdb, follow the instructions in the section on using detached debug symbols.
Reporting Bugs and Issues
Please report issues to the steam-runtime issue tracker.

The container runtimes have some known issues which do not need to be reported again.

## Steam-runtime Repository
The Steam-runtime SDK relies on an APT repository that Valve has created that holds the packages contained within the steam-runtime. A single package, steamrt-dev, lists all the steam-runtime development packages (i.e., packages that contain headers and files required to build software with those libraries, and whose names end in -dev) as dependencies. Conceptually, a base chroot environment is created in the traditional way using debootstrap; steamrt-dev is then installed into this, and a set of commonly used compilers and build tools are installed. It is expected that after this script sets the environment up, developers may want to install other packages/tools they may need into the chroot environment. If any of these packages contain runtime dependencies, then you will have to make sure to satisfy these yourself, as only the runtime dependencies of the steamrt-dev packages are included in the steam-runtime.

## Building in the Runtime
To prevent libraries from development and build machines 'leaking' into your applications, you should build within a Steam Runtime container or chroot environment.

We recommend using a Toolbox, rootless Podman, or Docker container for this:

## For Podman:

```bash

podman pull registry.gitlab.steamos.cloud/steamrt/scout/sdk
```
## For Docker:

```bash

sudo docker pull registry.gitlab.steamos.cloud/steamrt/scout/sdk
```
For more details, please consult the Steam Runtime SDK documentation.

Using a Debugger in the Build Environment
To get the detached debug symbols that are required for gdb and similar tools, you can download the matching com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-debug.tar.gz, unpack it (preserving directory structure), and use its files/ directory as the chroot or container's /usr/lib/debug.

For example, with Docker, you might unpack the tarball in /tmp/scout-dbgsym-0.20191024.0 and use something like:

```bash

sudo docker run \
--rm \
--init \
-v /home:/home \
-v /tmp/scout-dbgsym-0.20191024.0/files:/usr/lib/debug \
-e HOME=/home/user \
-u $(id -u):$(id -g) \
-h $(hostname) \
-v /tmp:/tmp \
-it \
steamrt_scout_amd64:latest \
/dev/init -sg -- /bin/bash
Or with schroot, you might create /var/chroots/steamrt_scout_amd64/usr/lib/debug/ and move the contents of files/ into it.
```
## Using Detached Debug Symbols
Please see doc/debug-symbols.md.



