# Images

This directory contains files necessary for building DAOS images using Packer and Ansible.

  > NOTE: At this time DAOS is installed from source because it requires patches to run on Azure.
  >

## Prerequisites Required

If you have not done so yet, please complete the steps in the [Prequisites](../docs/prerequisites.md) document.

## Accept Legal Terms of Base Image

The DAOS image is based on the Alma Linux 8 marketplace image.

In order to use this image you must accept the legal terms before running `packer`.

To accept the legal terms run

```bash
az vm image accept-terms --urn almalinux:almalinux:8-gen2:8.7.2022122801
```

## Create Shared Image Gallery

The DAOS image will be published in an image gallery.

If you do not already have an image gallery you will need to create one.

To create an image gallery

```bash
az sig create --resource-group "<resource_group>" --gallery-name daos_image_gallery
```

Underscores are used in the name because gallery names may not contain the -  character.

## Image Definition

Create an image definition within the image gallery.

az sig image-definition create \
   --resource-group "<resource_group>" \
   --gallery-name daos_image_gallery \
   --gallery-image-definition "daos-almalinux8" \
   --publisher daos \
   --offer daos \
   --sku 24 \
   --os-type Linux \
   --os-state specialized

## Building DAOS images

Ensure that the variables in the `daos-azure.env` file contain the proper values for your subscription (account), resource group, service principal, image gallery, image definition, etc.

To build the DAOS image run:

```bash
cd images
./build.sh
```

## Customizing the build

The `build.sh` script uses the environment variables defined in the `daos-azure.env` file.

To create the `daos-azure.env` file make a copy of `daos-azure.env.example` and set the variable values that are appropriate for your deployment.
