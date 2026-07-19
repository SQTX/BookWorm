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

// Reading sessions getters
QString StatisticsProvider::sessionAudioFilter() const { return m_sessionAudioFilter; }

void StatisticsProvider::setSessionAudioFilter(const QString &mode)
{
    if (m_sessionAudioFilter != mode) {
        m_sessionAudioFilter = mode;
        emit sessionAudioFilterChanged();
        refresh();
    }
}

int StatisticsProvider::currentStreak() const { return m_currentStreak; }
int StatisticsProvider::longestStreak() const { return m_longestStreak; }
int StatisticsProvider::sessionPagesTotal() const { return m_sessionPagesTotal; }
double StatisticsProvider::meanPagesPerReadingDay() const { return m_meanPagesPerReadingDay; }
QVariantList StatisticsProvider::pagesPerDay() const { return m_pagesPerDay; }
QVariantList StatisticsProvider::pagesByWeekday() const { return m_pagesByWeekday; }
QVariantList StatisticsProvider::recentSessions() const { return m_recentSessions; }

void StatisticsProvider::computeStreaks(const QVariantList &dates)
{
    m_currentStreak = 0;
    m_longestStreak = 0;

    if (dates.isEmpty())
        return;

    // Current streak counts back from today, or from yesterday if today has no
    // session yet — an evening reader should not see their streak reset each morning.
    const QDate today = QDate::currentDate();
    const QDate newest = dates.first().toDate();
    if (newest == today || newest == today.addDays(-1)) {
        QDate expected = newest;
        for (const QVariant &value : dates) {
            if (value.toDate() != expected)
                break;
            ++m_currentStreak;
            expected = expected.addDays(-1);
        }
    }

    // Longest streak: walk the whole list looking for consecutive runs.
    int run = 1;
    m_longestStreak = 1;
    for (int i = 1; i < dates.size(); ++i) {
        const QDate previous = dates.at(i - 1).toDate();
        const QDate current  = dates.at(i).toDate();
        if (current == previous.addDays(-1)) {
            ++run;
        } else {
            run = 1;
        }
        if (run > m_longestStreak)
            m_longestStreak = run;
    }
}

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

    // Reading sessions (year- and audio-mode-filtered)
    const QString audio = m_sessionAudioFilter;
    m_sessionPagesTotal = db.totalSessionPages(yr, audio);
    m_pagesPerDay        = db.pagesPerDay(yr, audio);
    m_pagesByWeekday     = db.pagesByWeekday(yr, audio);
    m_recentSessions     = db.recentSessions(yr, audio);

    const int readingDays = db.readingDayCount(yr, audio);
    m_meanPagesPerReadingDay = readingDays > 0
        ? static_cast<double>(m_sessionPagesTotal) / readingDays
        : 0.0;

    computeStreaks(db.sessionDates(yr, audio));

    emit dataChanged();
}
