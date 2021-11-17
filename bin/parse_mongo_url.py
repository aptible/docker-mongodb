#!/usr/bin/env python
"""
The output from this script is meant to be eval'd by a shell to parse out MongoDB options
from a connection string.

>>> os.environ["MONGO_VERSION"] = "100.0.0"
>>> set_use_ssl_opts(False)
>>> mongo_url = urlparse.urlparse("mongodb://aptible:foobar@localhost:123/db?ssl=true&x-sslVerify=false")
>>> options = prepare_options(mongo_url)
>>> assert use_tls_options() == True
>>> assert options["host"] == "localhost"
>>> assert options["port"] == 123
>>> assert options["username"] == "aptible"
>>> assert options["password"] == "foobar"
>>> assert "--tlsAllowInvalidCertificates" in options["mongo_options"]
>>> assert "--tls" in options["mongo_options"]
>>> assert "--sslAllowInvalidCertificates" not in options["mongo_options"]
>>> assert "--ssl" not in options["mongo_options"]
>>> set_use_ssl_opts(True)
>>> options = prepare_options(mongo_url)
>>> assert use_tls_options() == False
>>> assert "--sslAllowInvalidCertificates" in options["mongo_options"]
>>> assert "--ssl" in options["mongo_options"]
>>> assert "--tlsAllowInvalidCertificates" not in options["mongo_options"]
>>> assert "--tls" not in options["mongo_options"]

>>> set_use_ssl_opts(False)
>>> mongo_url = urlparse.urlparse("mongodb://aptible:foobar@localhost:123/db?ssl=true")
>>> options = prepare_options(mongo_url)
>>> assert use_tls_options() == True
>>> assert "--sslAllowInvalidCertificates" not in options["mongo_options"]
>>> assert "--tlsAllowInvalidCertificates" not in options["mongo_options"]
>>> assert "--tls" in options["mongo_options"]
>>> assert "--ssl" not in options["mongo_options"]
>>> set_use_ssl_opts(True)
>>> options = prepare_options(mongo_url)
>>> assert use_tls_options() == False
>>> assert "--sslAllowInvalidCertificates" not in options["mongo_options"]
>>> assert "--tlsAllowInvalidCertificates" not in options["mongo_options"]
>>> assert "--ssl" in options["mongo_options"]
>>> assert "--tls" not in options["mongo_options"]

>>> set_use_ssl_opts(False)
>>> os.environ["MONGO_VERSION"] = "4.0.0"
>>> assert use_tls_options() == False
>>> os.environ["MONGO_VERSION"] = "4.2.0"
>>> assert use_tls_options() == True
"""

import argparse
import os
import sys
import urlparse
from pipes import quote # pipes.quote is deprecated in 2.7, if upgrading to 3.x, use shlex.quote


DEFAULT_MONGO_PORT = 27017
SSL_CA_FILE = "/etc/ssl/certs/ca-certificates.crt"
use_ssl_opts = False

def set_use_ssl_opts(val):
    global use_ssl_opts
    use_ssl_opts = val

def get_mongo_version():
    """
    Parse MongoDB version from environment as numbers. Returns a dictionary of "major" version as a float and
    "minor" version as an integer.
    """
    parts = list(map(lambda v: int(v), os.environ["MONGO_VERSION"].split('.')))
    return {
        "major": float("%i.%i" %(parts[0], parts[1])),
        "minor": parts[2]
     }

def use_tls_options():
    """
    Starting in MongoDB 4.2, SSL options and parameters are deprecated so use the TLS equivalent unless
    --ssl-opts was specified.
    """
    return get_mongo_version()["major"] >= 4.2 and not use_ssl_opts

def qs_opt_eq(qs, opt, value):
    """
    Returns True if the query string option is equal to value.
    """
    for opt_value in qs.get(opt, []):
        if opt_value == value:
            return True

def qs_has_any_opt(qs, opts, ret=True):
    """
    Check if any of the specified options are in the query string. When ret=True, returns
    True if any of the options in the query string are "true"; otherwise returns False.
    When ret=False, returns False if any of the options in the query string are "false";
    otherwise returns True.
    """
    opt_value = str(ret).lower()

    for opt in opts:
        if qs_opt_eq(qs, opt, opt_value):
            return ret
    return not ret

def qs_uses_ssl(qs):
    """
    By default, we don't use SSL/TLS. If ?ssl=true or ?tls=true is found, we do.
    """
    return qs_has_any_opt(qs, ["ssl", "tls"])


def qs_checks_ssl(qs):
    """
    By default, we check SSL/TLS certificate validity. If ?x-sslVerify=false, ?sslAllowInvalidCertificates=true,
    or ?tlsAllowInvalidCertificates=true is found, we don't. We prepend x- to the sslVerify option because it's
    non-standard in MongoDB connection strings.
    """
    if qs_opt_eq(qs, "x-sslVerify", "false"):
        return False
    return not qs_has_any_opt(qs, ["sslAllowInvalidCertificates", "tlsAllowInvalidCertificates"])


def prepare_options(u):
    qs = urlparse.parse_qs(u.query)
    use_ssl = qs_uses_ssl(qs)
    check_ssl = qs_checks_ssl(qs)
    ssl_tls_prefix = "tls" if use_tls_options() else "ssl"

    # Prepare our Mongo options
    options = [
        "--host", u.hostname,
        "--port", str(u.port or DEFAULT_MONGO_PORT),
    ]

    for opt, val in zip(["username", "password"], [u.username, u.password]):
        if val:
            options.extend(["--{0}".format(opt), val])

    if use_ssl:
        options.extend(["--%s" %(ssl_tls_prefix), "--%sCAFile" %(ssl_tls_prefix), SSL_CA_FILE])
        if not check_ssl:
            options.append("--%sAllowInvalidCertificates" %(ssl_tls_prefix))

    return {
        "host": u.hostname,
        "port": u.port,
        "username": u.username,
        "password": u.password,
        "database": u.path.lstrip('/'),
        "mongo_options": options
    }


def sanity_check(u):
    if u.hostname is None:
        print >> sys.stderr, "URL must include hostname"
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mongo_url", help="The MongoDB URL string to parse")
    parser.add_argument("--ssl-opts", help="Use SSL options instead of TLS options", action="store_true")
    args = parser.parse_args()

    set_use_ssl_opts(args.ssl_opts)
    u = urlparse.urlparse(args.mongo_url)

    sanity_check(u)

    # And now provide this to the shell
    for k, v in prepare_options(u).items():
        if isinstance(v, list):
            array = "({0})".format(" ".join([quote(o) for o in v]))
            print "{0}={1}".format(k, array)
        else:
            print "{0}={1}".format(k, quote(str(v)))



if __name__ == "__main__":
    main()
