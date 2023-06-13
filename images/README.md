# Images

This directory contains files necessary for building DAOS images using Packer and Ansible.

  > NOTE: At this time DAOS is installed from source because it requires patches to run on Azure.
  >

## Prerequisites Required

If you have not done so yet, please complete the steps in the [Prequisites](../docs/prerequisites.md) document.

## Building DAOS images

To build the images with the default settings run:

```bash
cd images
./build.sh
```

## Customizing the build

The `build.sh` script uses environment variables that can be overriden to install different versions of DAOS on different distros or distro versions. This allows images to be built as part of a CI workflow.

The `build.env.example` file contains a list of environment variables that can be overriden to customize the image build.

The variables either need to be exported prior to running `build.sh` or they can exist in a file. The path to the file can be passed as an argument to `build.sh` which will source the file before performing the build.

You can copy the `build.env.example` file, make any necessary  changes, then pass the path of the `.env` file as an argument to `build.sh`.

For example:

```bash
cd images
cp build.env.example build.env
# Make changes to build.env
./build.sh build.env
```
