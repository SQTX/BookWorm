#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

class StatisticsProvider : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int totalBooksRead READ totalBooksRead NOTIFY dataChanged)
    Q_PROPERTY(int totalPagesRead READ totalPagesRead NOTIFY dataChanged)
    Q_PROPERTY(double averageRating READ averageRating NOTIFY dataChanged)
    Q_PROPERTY(QVariantList genreDistribution READ genreDistribution NOTIFY dataChanged)
    Q_PROPERTY(QVariantList booksPerMonth READ booksPerMonth NOTIFY dataChanged)

public:
    explicit StatisticsProvider(QObject *parent = nullptr);

    int totalBooksRead() const;
    int totalPagesRead() const;
    double averageRating() const;
    QVariantList genreDistribution() const;
    QVariantList booksPerMonth() const;

    Q_INVOKABLE void refresh();

signals:
    void dataChanged();

private:
    int m_totalBooksRead = 0;
    int m_totalPagesRead = 0;
    double m_averageRating = 0.0;
    QVariantList m_genreDistribution;
    QVariantList m_booksPerMonth;
};
