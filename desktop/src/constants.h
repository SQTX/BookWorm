#pragma once

#include <QByteArray>
#include <QString>

namespace BookWorm::Config {
    inline constexpr auto DB_DRIVER   = "QPSQL";

    inline constexpr auto APP_NAME    = "BookWorm";
    inline constexpr auto APP_VERSION = "1.5.0";
    inline constexpr auto APP_ORG     = "sqtx";

    /**
     * Database connection, overridable from the environment.
     *
     * These were compile-time constants, which made the schema untestable: the
     * application could only ever open the live library, so a migration could
     * not be tried against a restored copy first. That is not a hypothetical —
     * it is how an untested migration reached the real database, and it would
     * have mattered a great deal had the migration been wrong instead of right.
     *
     *   BOOKWORM_DB_NAME=wormbook_scratch ./BookWorm
     *
     * The defaults are the previous constants, so an ordinary launch behaves
     * exactly as before and nobody has to configure anything.
     */
    inline QString envOr(const char *name, const QString &fallback)
    {
        const QByteArray value = qgetenv(name);
        return value.isEmpty() ? fallback : QString::fromLocal8Bit(value);
    }

    inline QString dbHost()     { return envOr("BOOKWORM_DB_HOST", QStringLiteral("localhost")); }
    inline QString dbName()     { return envOr("BOOKWORM_DB_NAME", QStringLiteral("wormbook")); }
    inline QString dbUser()     { return envOr("BOOKWORM_DB_USER", QStringLiteral("sqtx")); }
    inline QString dbPassword() { return envOr("BOOKWORM_DB_PASSWORD", QString()); }

    inline int dbPort()
    {
        bool ok = false;
        const int port = envOr("BOOKWORM_DB_PORT", QStringLiteral("5432")).toInt(&ok);
        return (ok && port > 0 && port <= 65535) ? port : 5432;
    }
}
