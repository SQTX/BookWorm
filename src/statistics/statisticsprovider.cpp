#include "statisticsprovider.h"
#include "../database/databasemanager.h"

#include <QDate>

StatisticsProvider::StatisticsProvider(QObject *parent)
    : QObject(parent)
{
}

// Year filter
int StatisticsProvider::selectedYear() const { return m_selectedYear; }
void StatisticsProvider::setSelectedYear(int year)
{
    if (m_selectedYear == year)
        return;
    m_selectedYear = year;
    emit selectedYearChanged();
    refresh();
}
QVariantList StatisticsProvider::availableYears() const { return m_availableYears; }

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

    int yr = m_selectedYear;  // 0 = all years

    // Available years (always global)
    m_availableYears = db.getAvailableYears();

    // Existing (year-filtered)
    m_totalBooksRead    = db.totalBooksRead(yr);
    m_totalPagesRead    = db.totalPagesRead(yr);
    m_averageRating     = db.averageRating(yr);
    m_genreDistribution = db.genreDistribution(yr);
    m_booksPerMonth     = db.booksPerMonth();

    // Extended (year-filtered)
    m_totalBooks                 = db.totalBooks(yr);
    m_averagePagesPerBook        = db.averagePagesPerBook(yr);
    m_averageCompletionPercent   = db.averageCompletionPercent(yr);
    m_booksPerYear               = db.booksPerYear();
    m_statusDistribution         = db.statusDistribution(yr);

    // Monthly chart: use selectedYear if set, otherwise current year
    int chartYear = (yr > 0) ? yr : QDate::currentDate().year();
    m_booksPerMonthCurrentYear   = db.booksPerMonthForYear(chartYear);
    m_booksPerMonthPreviousYear  = db.booksPerMonthForYear(chartYear - 1);

    emit dataChanged();
}
