#pragma once

#include <QSqlDatabase>
#include <QVector>
#include <QVariantList>
#include <QPair>
#include <QDate>
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
    QVariantList fetchAllTagsWithColors();
    bool addTagWithColor(const QString &name, const QString &color);
    bool updateTag(int id, const QString &name, const QString &color);
    bool deleteTag(int id);
    bool syncTagsForBook(int bookId, const QStringList &tags);

    // Quotes
    QVariantList fetchQuotesForBook(int bookId);
    bool addQuote(int bookId, const QString &quote, int page);
    bool removeQuote(int quoteId);

    // Highlights
    QVariantList fetchHighlightsForBook(int bookId);
    bool addHighlight(int bookId, const QString &title, int page, const QString &note);
    bool removeHighlight(int highlightId);

    // Challenges
    QVariantList fetchAllChallenges();
    int insertChallenge(const QString &name, int targetBooks, const QDate &deadline);
    bool deleteChallenge(int id);
    QVariantList fetchBooksForChallenge(int challengeId);

    // Reset
    bool resetAllData();

    // Statistics (year=0 means all years)
    int totalBooksRead(int year = 0);
    int totalPagesRead(int year = 0);
    double averageRating(int year = 0);
    QVariantList genreDistribution(int year = 0);
    QVariantList booksPerMonth();

    // Statistics (extended)
    int totalBooks(int year = 0);
    double averagePagesPerBook(int year = 0);
    double averageCompletionPercent(int year = 0);
    QVariantList booksPerYear();
    QVariantList booksPerMonthForYear(int year);
    QVariantMap statusDistribution(int year = 0);
    QVariantList getAvailableYears();

private:
    DatabaseManager() = default;
    ~DatabaseManager();
    DatabaseManager(const DatabaseManager &) = delete;
    DatabaseManager &operator=(const DatabaseManager &) = delete;

    QSqlDatabase m_db;
};
