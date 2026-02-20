#include "book.h"
#include <QVariant>

QVariantMap Book::toVariantMap() const
{
    QVariantMap map;
    map["id"]              = id;
    map["title"]           = title;
    map["author"]          = author;
    map["genre"]           = genre;
    map["pageCount"]       = pageCount;
    map["startDate"]       = startDate.isValid() ? startDate.toString(Qt::ISODate) : QString();
    map["endDate"]         = endDate.isValid() ? endDate.toString(Qt::ISODate) : QString();
    map["rating"]          = rating;
    map["status"]          = status;
    map["notes"]           = notes;
    map["isbn"]            = isbn;
    map["publisher"]       = publisher;
    map["publicationYear"] = publicationYear;
    map["publicationDate"] = publicationDate.isValid() ? publicationDate.toString(Qt::ISODate) : QString();
    map["language"]        = language;
    map["coverImagePath"]  = coverImagePath;
    map["itemType"]        = itemType;
    map["isNonFiction"]    = isNonFiction;
    map["currentPage"]     = currentPage;
    map["series"]          = series;
    map["tags"]            = tags.join(", ");
    return map;
}

Book Book::fromVariantMap(const QVariantMap &map)
{
    Book b;
    b.id              = map.value("id", -1).toInt();
    b.title           = map.value("title").toString().trimmed();
    b.author          = map.value("author").toString().trimmed();
    b.genre           = map.value("genre").toString().trimmed();
    b.pageCount       = map.value("pageCount", 0).toInt();
    b.startDate       = QDate::fromString(map.value("startDate").toString(), Qt::ISODate);
    b.endDate         = QDate::fromString(map.value("endDate").toString(), Qt::ISODate);
    b.rating          = map.value("rating", 0).toInt();
    b.status          = map.value("status", "planned").toString();
    b.notes           = map.value("notes").toString();
    b.isbn            = map.value("isbn").toString().trimmed();
    b.publisher       = map.value("publisher").toString().trimmed();
    b.publicationYear = map.value("publicationYear", 0).toInt();
    b.publicationDate = QDate::fromString(map.value("publicationDate").toString(), Qt::ISODate);
    b.language        = map.value("language", "English").toString();
    b.coverImagePath  = map.value("coverImagePath").toString();
    b.itemType        = map.value("itemType", "book").toString();
    b.isNonFiction    = map.value("isNonFiction", false).toBool();
    b.currentPage     = map.value("currentPage", 0).toInt();
    b.series          = map.value("series").toString().trimmed();

    const QString tagsStr = map.value("tags").toString();
    if (!tagsStr.isEmpty()) {
        const auto parts = tagsStr.split(',');
        for (const auto &part : parts) {
            const QString trimmed = part.trimmed();
            if (!trimmed.isEmpty())
                b.tags.append(trimmed);
        }
    }

    return b;
}

Book Book::fromSqlRecord(const QSqlRecord &record)
{
    Book b;
    b.id              = record.value("id").toInt();
    b.title           = record.value("title").toString();
    b.author          = record.value("author").toString();
    b.genre           = record.value("genre").toString();
    b.pageCount       = record.value("page_count").toInt();
    b.startDate       = record.value("start_date").toDate();
    b.endDate         = record.value("end_date").toDate();
    b.rating          = record.value("rating").toInt();
    b.status          = record.value("status").toString();
    b.notes           = record.value("notes").toString();
    b.isbn            = record.value("isbn").toString();
    b.publisher       = record.value("publisher").toString();
    b.publicationYear = record.value("publication_year").toInt();
    b.publicationDate = record.value("publication_date").toDate();
    b.language        = record.value("language").toString();
    b.coverImagePath  = record.value("cover_image_path").toString();
    b.itemType        = record.value("item_type").toString();
    if (b.itemType.isEmpty()) b.itemType = QStringLiteral("book");
    b.isNonFiction    = record.value("is_non_fiction").toBool();
    b.currentPage     = record.value("current_page").toInt();
    b.series          = record.value("series").toString();
    return b;
}
