#pragma once

#include <QSqlDatabase>
#include <QVector>
#include <QVariantList>
#include <QPair>
#include <optional>

#include "../models/book.h"

class DatabaseManager
{
public:
    static DatabaseManager &instance();

    bool connect();
    void disconnect();
    bool isConnected() const;

    bool initializeSchema();

    // Book CRUD
    QVector<Book> fetchAllBooks();
    std::optional<Book> fetchBookById(int id);
    int  insertBook(const Book &book);
    bool updateBook(const Book &book);
    bool deleteBook(int id);

    // Tags
    QStringList fetchTagsForBook(int bookId);
    QStringList fetchAllTags();
    bool syncTagsForBook(int bookId, const QStringList &tags);

    // Quotes
    QVariantList fetchQuotesForBook(int bookId);
    bool addQuote(int bookId, const QString &quote, int page);
    bool removeQuote(int quoteId);

    // Statistics
    int totalBooksRead();
    int totalPagesRead();
    double averageRating();
    QVariantList genreDistribution();
    QVariantList booksPerMonth();

private:
    DatabaseManager() = default;
    ~DatabaseManager();
    DatabaseManager(const DatabaseManager &) = delete;
    DatabaseManager &operator=(const DatabaseManager &) = delete;

    QSqlDatabase m_db;
};
