/*
 * 9p
 *
 * Copyright IBM, Corp. 2010
 *
 * Authors:
 *  Gautham R Shenoy <ego@in.ibm.com>
 *
 * This work is licensed under the terms of the GNU GPL, version 2.  See
 * the COPYING file in the top-level directory.
 *
 */

#include "qemu/osdep.h"
#include "qapi/error.h"
#include "qemu-fsdev.h"
#include "qemu/config-file.h"
#include "qapi/qapi-commands-fsdev.h"

int qemu_fsdev_add(QemuOpts *opts, Error **errp)
{
    return 0;
}

void qmp_fsdev_add(FsdevAdd *add, Error **errp)
{
    error_setg(errp, "9p filesystem support is not compiled in");
}
