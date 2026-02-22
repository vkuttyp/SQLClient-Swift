#ifndef CFREETDS_H
#define CFREETDS_H

#pragma once

#ifdef __APPLE__
    #include "/usr/local/opt/freetds/include/sybdb.h"
    #include "/usr/local/opt/freetds/include/sybfront.h"
#else
    #include <sybdb.h>
    #include <sybfront.h>
#endif

#endif /* CFREETDS_H */
