#include "statisticsprovider.h"
#include "../database/databasemanager.h"

StatisticsProvider::StatisticsProvider(QObject *parent)
    : QObject(parent)
{
}

int StatisticsProvider::totalBooksRead() const { return m_totalBooksRead; }
int StatisticsProvider::totalPagesRead() const { return m_totalPagesRead; }
double StatisticsProvider::averageRating() const { return m_averageRating; }
QVariantList StatisticsProvider::genreDistribution() const { return m_genreDistribution; }
QVariantList StatisticsProvider::booksPerMonth() const { return m_booksPerMonth; }

void StatisticsProvider::refresh()
{
    auto &db = DatabaseManager::instance();

    m_totalBooksRead    = db.totalBooksRead();
    m_totalPagesRead    = db.totalPagesRead();
    m_averageRating     = db.averageRating();
    m_genreDistribution = db.genreDistribution();
    m_booksPerMonth     = db.booksPerMonth();

    emit dataChanged();
}
