#include "statisticsprovider.h"
#include "../database/databasemanager.h"

#include <QDate>

StatisticsProvider::StatisticsProvider(QObject *parent)
    : QObject(parent)
{
}

// Existing getters
int StatisticsProvider::totalBooksRead() const { return m_totalBooksRead; }
int StatisticsProvider::totalPagesRead() const { return m_totalPagesRead; }
double StatisticsProvider::averageRating() const { return m_averageRating; }
QVariantList StatisticsProvider::genreDistribution() const { return m_genreDistribution; }
QVariantList StatisticsProvider::booksPerMonth() const { return m_booksPerMonth; }

// Extended getters
int StatisticsProvider::totalBooks() const { return m_totalBooks; }
double StatisticsProvider::averagePagesPerBook() const { return m_averagePagesPerBook; }
double StatisticsProvider::averageCompletionPercent() const { return m_averageCompletionPercent; }
QVariantList StatisticsProvider::booksPerYear() const { return m_booksPerYear; }
QVariantList StatisticsProvider::booksPerMonthCurrentYear() const { return m_booksPerMonthCurrentYear; }
QVariantList StatisticsProvider::booksPerMonthPreviousYear() const { return m_booksPerMonthPreviousYear; }
QVariantMap StatisticsProvider::statusDistribution() const { return m_statusDistribution; }

void StatisticsProvider::refresh()
{
    auto &db = DatabaseManager::instance();

    // Existing
    m_totalBooksRead    = db.totalBooksRead();
    m_totalPagesRead    = db.totalPagesRead();
    m_averageRating     = db.averageRating();
    m_genreDistribution = db.genreDistribution();
    m_booksPerMonth     = db.booksPerMonth();

    // Extended
    m_totalBooks                 = db.totalBooks();
    m_averagePagesPerBook        = db.averagePagesPerBook();
    m_averageCompletionPercent   = db.averageCompletionPercent();
    m_booksPerYear               = db.booksPerYear();
    m_statusDistribution         = db.statusDistribution();

    int currentYear = QDate::currentDate().year();
    m_booksPerMonthCurrentYear   = db.booksPerMonthForYear(currentYear);
    m_booksPerMonthPreviousYear  = db.booksPerMonthForYear(currentYear - 1);

    emit dataChanged();
}
