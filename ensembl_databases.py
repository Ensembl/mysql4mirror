#!/usr/bin/env python3

"""
.. See the NOTICE file distributed with this work for additional information
   regarding copyright ownership.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.

   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
"""

import os
from os import path
import gzip
import ftplib
import json
import argparse
import fnmatch
import re
import math

# CHANGE THE LOOKUP FILE BY SETTING ENSEMBL_DBLOOKUP
# LOOKUP REQUIRES THE FORMAT
# { dbname : { database : "dbname", path: "/pub/path", server : "ftp.ensembl.org" } }
def dblookup():
    default_lookup = path.join(path.split(path.abspath(__file__))[0], "dblookup.json")
    dblookup = os.environ.get("ENSEMBL_DBLOOKUP", default_lookup)
    with open(dblookup, "r") as file:
        return json.load(file)


def main():
    parser = argparse.ArgumentParser(description="Download Ensembl databases")
    parser.add_argument(
        "databases",
        metavar="DB",
        type=str,
        nargs="*",
        help="Specify the database name to download. Can use UNIX style glob matching to find multiple databases but quote to avoid command line globbing ",
    )
    parser.add_argument(
        "-l",
        "--list",
        action="store_true",
        help="List available databases. Can filter using DB",
    )
    parser.add_argument(
        "-i",
        "--info",
        action="store_true",
        help="Return a JSON blob of database information. Can filter using DB",
    )
    parser.add_argument(
        "-d",
        "--download",
        action="store_true",
        help="Download files as specified by DB",
    )
    parser.add_argument(
        "-v",
        "--validate",
        action="store_true",
        help="Validate files. Can filter using DB. Assumes files have been already downloaded",
    )
    parser.add_argument(
        "-b",
        "--basedir",
        type=str,
        default=os.path.curdir,
        help="Give an optional path to where database dumps should be located/worked with",
    )

    args = parser.parse_args()
    lookup = dblookup()

    available_dbs = []
    for db in args.databases:
        matching = fnmatch.filter(lookup.keys(), db)
        available_dbs.extend(matching)

    # just list the keys of the lookup
    if args.list:
        if not args.databases:
            available_dbs = lookup.keys()
        for db in available_dbs:
            print(db)
        return

    # add all info into an array & print (there's a better way to do this for sure)
    if args.info:
        dbs = [lookup.get(x) for x in available_dbs]
        print(json.dumps(dbs, indent=2))
        return

    # Download the database by connecting to the FTP server, listing all files, then downloading
    if args.download:
        for db in available_dbs:
            dbinfo = lookup.get(db)
            server = dbinfo.get("server")
            database = dbinfo.get("database")
            local_dir = path.join(args.basedir, database)
            ftp_target = dbinfo.get("path")

            if not path.exists(local_dir):
                os.mkdir(local_dir)

            print("Logging into " + server)
            ftp = ftplib.FTP()
            ftp.connect(server)
            ftp.login()

            print("Listing database files for " + database)
            ftp.cwd(ftp_target)
            for f in ftp.nlst():
                local_target = path.join(local_dir, f)
                print("Downloading " + local_target)
                with open(local_target, "wb") as localfile:
                    ftp.retrbinary("RETR " + f, localfile.write)

            ftp.quit()
            ftp.close()

    # Open CHECKSUMS.gz, calculate sum for each one & make sure the files have downloaded correctly
    if args.validate:
        if not available_dbs:
            print("No databases found to test")
            os.sys.exit(0)
        fail = False
        for dbname in available_dbs:
            db = path.join(args.basedir, dbname)
            if not path.exists(db):
                print('Cannot find database directory "' + db + '"')
                fail = True
                break
            with gzip.open(path.join(db, "CHECKSUMS.gz"), "rt") as file:
                checksums = [
                    tuple(re.split("\s+", x.strip())) for x in file.readlines()
                ]
            for chk in checksums:
                target_file = path.join(db, chk[2])
                local_chk = (bsdchecksum(target_file), blocks(target_file), chk[2])
                if local_chk != chk:
                    print(
                        "Checksum check failed for {0} and {1}. Expected '{2} {3}' but got '{4} {5}'".format(
                            db, chk[2], chk[0], chk[1], local_chk[0], local_chk[1]
                        )
                    )
                    fail = True
        if fail:
            os.sys.exit(1)
        else:
            print("All files are correct")


def bsdchecksum(infile):
    """Compute BSD checksum as defined by https://en.wikipedia.org/wiki/BSD_checksum

    :param infile: File location to query
    :type infile: filepath

    :return: Calculated checksum
    :rtype: str
    """
    with open(infile, "rb", buffering=5) as f:
        checksum = 0
        byte = f.read(1)
        while byte:
            checksum = (checksum >> 1) + ((checksum & 1) << 15)
            checksum += int.from_bytes(byte, byteorder="big")
            checksum &= 0xFFFF
            byte = f.read(1)
    return str(checksum)


def blocks(infile):
    """Return the number of 1024 blocks available in the given file calculated by dividing st_size by 1024 and ceil the number

    :param infile: File location to query
    :type infile: filepath
    :return: Numbers of blocks in the given file.
    :rtype: str
    """
    byte_size = os.stat(infile).st_size
    return str(math.ceil(byte_size / 1024))


if __name__ == "__main__":
    main()
