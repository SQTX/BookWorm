#pragma once

#include <QString>

namespace WormBook::Config {
    inline constexpr auto DB_DRIVER   = "QPSQL";
    inline constexpr auto DB_HOST     = "localhost";
    inline constexpr int  DB_PORT     = 5432;
    inline constexpr auto DB_NAME     = "wormbook";
    inline constexpr auto DB_USER     = "sqtx";
    inline constexpr auto DB_PASSWORD = "";

    inline constexpr auto APP_NAME    = "WormBook";
    inline constexpr auto APP_VERSION = "1.0.0";
    inline constexpr auto APP_ORG     = "sqtx";
}
