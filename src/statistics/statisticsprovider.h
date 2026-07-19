#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

class StatisticsProvider : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Year filter
    Q_PROPERTY(int selectedYear READ selectedYear WRITE setSelectedYear NOTIFY selectedYearChanged)
    Q_PROPERTY(QVariantList availableYears READ availableYears NOTIFY dataChanged)

    // Existing
    Q_PROPERTY(int totalBooksRead READ totalBooksRead NOTIFY dataChanged)
    Q_PROPERTY(int totalPagesRead READ totalPagesRead NOTIFY dataChanged)
    Q_PROPERTY(double averageRating READ averageRating NOTIFY dataChanged)
    Q_PROPERTY(QVariantList genreDistribution READ genreDistribution NOTIFY dataChanged)
    Q_PROPERTY(QVariantList booksPerMonth READ booksPerMonth NOTIFY dataChanged)

    // Extended
    Q_PROPERTY(int totalBooks READ totalBooks NOTIFY dataChanged)
    Q_PROPERTY(double averagePagesPerBook READ averagePagesPerBook NOTIFY dataChanged)
    Q_PROPERTY(double averageCompletionPercent READ averageCompletionPercent NOTIFY dataChanged)
    Q_PROPERTY(QVariantList booksPerYear READ booksPerYear NOTIFY dataChanged)
    Q_PROPERTY(QVariantList booksPerMonthCurrentYear READ booksPerMonthCurrentYear NOTIFY dataChanged)
    Q_PROPERTY(QVariantList booksPerMonthPreviousYear READ booksPerMonthPreviousYear NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap statusDistribution READ statusDistribution NOTIFY dataChanged)

    // Reading sessions
    Q_PROPERTY(QString sessionAudioFilter READ sessionAudioFilter WRITE setSessionAudioFilter NOTIFY sessionAudioFilterChanged)
    Q_PROPERTY(int currentStreak READ currentStreak NOTIFY dataChanged)
    Q_PROPERTY(int longestStreak READ longestStreak NOTIFY dataChanged)
    Q_PROPERTY(int sessionPagesTotal READ sessionPagesTotal NOTIFY dataChanged)
    Q_PROPERTY(double meanPagesPerReadingDay READ meanPagesPerReadingDay NOTIFY dataChanged)
    Q_PROPERTY(QVariantList pagesPerDay READ pagesPerDay NOTIFY dataChanged)
    Q_PROPERTY(QVariantList pagesByWeekday READ pagesByWeekday NOTIFY dataChanged)
    Q_PROPERTY(QVariantList recentSessions READ recentSessions NOTIFY dataChanged)

public:
    explicit StatisticsProvider(QObject *parent = nullptr);

    // Year filter
    int selectedYear() const;
    void setSelectedYear(int year);
    QVariantList availableYears() const;

    // Existing
    int totalBooksRead() const;
    int totalPagesRead() const;
    double averageRating() const;
    QVariantList genreDistribution() const;
    QVariantList booksPerMonth() const;

    // Extended
    int totalBooks() const;
    double averagePagesPerBook() const;
    double averageCompletionPercent() const;
    QVariantList booksPerYear() const;
    QVariantList booksPerMonthCurrentYear() const;
    QVariantList booksPerMonthPreviousYear() const;
    QVariantMap statusDistribution() const;

    // Reading sessions
    QString sessionAudioFilter() const;
    void setSessionAudioFilter(const QString &mode);
    int currentStreak() const;
    int longestStreak() const;
    int sessionPagesTotal() const;
    double meanPagesPerReadingDay() const;
    QVariantList pagesPerDay() const;
    QVariantList pagesByWeekday() const;
    QVariantList recentSessions() const;

    Q_INVOKABLE void refresh();

signals:
    void dataChanged();
    void selectedYearChanged();
    void sessionAudioFilterChanged();

private:
    void computeStreaks(const QVariantList &dates);

    // Year filter
    int m_selectedYear = 0;  // 0 = all years
    QVariantList m_availableYears;

    // Existing
    int m_totalBooksRead = 0;
    int m_totalPagesRead = 0;
    double m_averageRating = 0.0;
    QVariantList m_genreDistribution;
    QVariantList m_booksPerMonth;

    // Extended
    int m_totalBooks = 0;
    double m_averagePagesPerBook = 0.0;
    double m_averageCompletionPercent = 0.0;
    QVariantList m_booksPerYear;
    QVariantList m_booksPerMonthCurrentYear;
    QVariantList m_booksPerMonthPreviousYear;
    QVariantMap m_statusDistribution;

    // Reading sessions
    QString m_sessionAudioFilter;  // empty = any audio mode
    int m_currentStreak = 0;
    int m_longestStreak = 0;
    int m_sessionPagesTotal = 0;
    double m_meanPagesPerReadingDay = 0.0;
    QVariantList m_pagesPerDay;
    QVariantList m_pagesByWeekday;
    QVariantList m_recentSessions;
};
