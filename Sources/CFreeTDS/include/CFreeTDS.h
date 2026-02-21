#ifndef CFREETDS_H
#define CFREETDS_H

#ifdef __APPLE__
#include "/opt/homebrew/opt/freetds/include/sybdb.h"
#include "/opt/homebrew/opt/freetds/include/sybfront.h"
#else
#include <sybdb.h>
#include <sybfront.h>
#endif

#endif /* CFREETDS_H */
