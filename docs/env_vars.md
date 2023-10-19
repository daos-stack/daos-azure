# DAOS on Azure - Environment Variables

This document provides information about the environment variables used by the
scripts in the `daos-stack/daos-azure` repo.

## The `daos-azure.env` file

The bash scripts and Bicep files in the `daos-stack/daos-azure` repo get their parameters from a single
environment file named `daos-azure.env` in the root of the repository. The
environment variables will also be used in cloud-init scripts on the VMs
and by Ansible playbooks that are run by cloud-init. This means that if you
want to make changes to your deployment, most likely you will do so by changing
the values of the environment variables in the `daos-azure.env` file.

The bash scripts in the `bin` directory take a `-e | --env-file` option
to specify the path to an environment file. This allows multiple `.env` files
to be used for different deployment scenarios.

If the `-e | --env-file` option is not passed, the scripts look for
a `daos-azure.env` file in the root of the repo.

You will need to create the `daos-azure.env` file in the root of the repo.

The `daos-azure.env.example` file contains a list of variables with default
settings.

To create the `daos-azure.env` file make a copy of the `daos-azure.env.example` file.

```bash
cp daos-azure.env.example daos-azure.env
```

After creating the file you will only need to edit a few variable values that
are user specific.  The variables that you need to set have values enclosed in
'< >' brackets.

There are only a few variables that user specific.

If you plan to deploy *infrastructure* resources with the `bin/infrastructure.sh`
script, you only need to set the variables that have values that are enclosed in
'< >' brackets.

If you have deployed your own *infrastructure* resources or you have pre-existing
*infrastructure* resources that you will use for DAOS, you will need to update the variable
values accordingly.

To see a list of the variables you must update run:

```bash
grep -e '"<.*>"' ../daos-azure.env.example
```

Example output:

```
DAOS_AZ_CORE_ACCT_NAME="<subscription_name>"
DAOS_AZ_CORE_LOCATION="<location>"
DAOS_AZ_SSH_ADMIN_KEY="<path_to_private_ssh_key>"
DAOS_AZ_SSH_ADMIN_KEY_PUB="<path_to_public_ssh_key>"
```

## Naming Convention

`DAOS_AZ_<section>[_<subsection>]_<var_name>`

The subsection is optional.

**Examples:**

- DAOS_AZ_CORE_ACCT_NAME
- DAOS_AZ_CORE_LOCATION
- DAOS_AZ_ARM_NET_SUBNET_NAME
- DAOS_AZ_ARM_NET_VNET_NAME

### Prefix

All variables that are used by the scripts in the `daos-stack/daos-azure` repo
are prefixed with `DAOS_AZ`.

This is to avoid any conflicts with environment variables used by either DAOS or Azure.

This also allows you to grep the entire repo for the prefix to find all of the
places where the variables are used.

### Section and subsection

The section and optional subsection portion of the variable name allow variables
to sort so they are grouped together.

### Name

The <var_name> portion can be multiple words separated by underscores.


## Default Variable Values

Scripts in this repo use the following convention for setting variable values.

```bash
VAR="${VAR:=${PREFIX:+${PREFIX}-}foo}"
```

Another way to write this would be

```bash
: "${VAR:=${PREFIX:+${PREFIX}-}foo}"
```

Let's break it down.

**`${VAR:=foo}`**

This syntax is saying "if VAR is unset or null, replace it with foo".

So if VAR has been previously set to something, it will retain its value; otherwise,
it gets the value foo.

Sometimes you will see `${VAR:-foo}` which is a slight variation.

The ':-' operator will return foo if VAR is unset or null but it won't actually
set the VAR value to foo.

The ':=' operator will actually set the VAR value to foo.

**`${PREFIX:+${PREFIX}-}`**

This syntax is saying "if PREFIX is set and not null, replace it with
${PREFIX}-". So, if PREFIX has a value of, say, "pre", this part would evaluate
to "pre-".

Combining the above two: The expression ${PREFIX:+${PREFIX}-}foo is evaluated
first. If PREFIX is set and not null, this expression will evaluate to
${PREFIX}-foo. If PREFIX is unset or null, it will evaluate to foo.

**`VAR="${VAR:=${PREFIX:+${PREFIX}-}foo}`**

 This is saying "if VAR is unset or null, set it to the result of the expression
 ${PREFIX:+${PREFIX}-}foo".

In summary, this line is conditionally prefixing foo with the content of
PREFIX and a hyphen only if PREFIX is set and not null, and then assigning that
to VAR, if VAR is unset or null.

You can also think of it like this:

```
if VAR is already set
  return VAR
else
  if PREFIX is set
    return "${PREFIX}-foo"
  else
    return "foo"
```

This allows you to set some variables in your environment and override the
values in the `daos-azure.env` file without actually modifying the file.

While this can be problematic if you exit your shell and lose your environment
variables, it can come in handy during development.
