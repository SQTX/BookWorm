#pragma once

#include <QString>
#include <QDate>
#include <QStringList>
#include <QVariantMap>
#include <QSqlRecord>

struct Book {
    int id = -1;
    QString title;
    QString author;
    QString genre;
    int pageCount = 0;
    QDate startDate;
    QDate endDate;
    int rating = 0;
    QString status = QStringLiteral("planned");
    QString notes;
    QString isbn;
    QString publisher;
    int publicationYear = 0;
    QDate publicationDate;
    QString language = QStringLiteral("English");
    QString coverImagePath;
    QString itemType = QStringLiteral("book");
    bool isNonFiction = false;
    int currentPage = 0;
    QString series;
    QString summary;
    QString review;
    QStringList tags;

    QVariantMap toVariantMap() const;
    static Book fromVariantMap(const QVariantMap &map);
    static Book fromSqlRecord(const QSqlRecord &record);
};
