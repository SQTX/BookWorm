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

    Q_INVOKABLE void refresh();

signals:
    void dataChanged();
    void selectedYearChanged();

private:
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
};
