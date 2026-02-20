#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>
#include "../models/bookmodel.h"

class BookController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(BookModel* model READ model CONSTANT)
    Q_PROPERTY(QString filterStatus READ filterStatus WRITE setFilterStatus NOTIFY filterStatusChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(int filterYear READ filterYear WRITE setFilterYear NOTIFY filterYearChanged)
    Q_PROPERTY(QString filterYearMode READ filterYearMode WRITE setFilterYearMode NOTIFY filterYearModeChanged)
    Q_PROPERTY(QString sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)

public:
    explicit BookController(QObject *parent = nullptr);

    BookModel *model() const;

    Q_INVOKABLE void loadBooks();
    Q_INVOKABLE bool addBook(const QVariantMap &bookData);
    Q_INVOKABLE bool updateBook(const QVariantMap &bookData);
    Q_INVOKABLE bool deleteBook(int id);
    Q_INVOKABLE QVariantMap getBookDetails(int id);

    Q_INVOKABLE QStringList getAllTags();
    Q_INVOKABLE QVariantList getAllTagsWithColors();
    Q_INVOKABLE bool addTag(const QString &name, const QString &color);
    Q_INVOKABLE bool updateTag(int id, const QString &name, const QString &color);
    Q_INVOKABLE bool deleteTag(int id);
    Q_INVOKABLE QVariantList getAvailableYears();
    Q_INVOKABLE QStringList getAllGenres();
    Q_INVOKABLE QStringList getAllSeries();
    Q_INVOKABLE QStringList getAllAuthors();
    Q_INVOKABLE QStringList getAllPublishers();
    Q_INVOKABLE QStringList getSeriesForAuthor(const QString &author);
    Q_INVOKABLE QStringList getDefaultGenres();

    Q_INVOKABLE bool addQuote(int bookId, const QString &quote, int page);
    Q_INVOKABLE bool removeQuote(int quoteId);
    Q_INVOKABLE QVariantList getQuotesForBook(int bookId);

    Q_INVOKABLE bool addHighlight(int bookId, const QString &title, int page, const QString &note);
    Q_INVOKABLE bool removeHighlight(int highlightId);
    Q_INVOKABLE QVariantList getHighlightsForBook(int bookId);

    Q_INVOKABLE bool updateSummary(int bookId, const QString &summary);
    Q_INVOKABLE bool updateReview(int bookId, const QString &review);

    Q_INVOKABLE QVariantMap getTypeDistribution();

    // Challenges
    Q_INVOKABLE QVariantList getChallenges();
    Q_INVOKABLE bool addChallenge(const QString &name, int targetBooks, const QString &deadline);
    Q_INVOKABLE bool deleteChallenge(int id);
    Q_INVOKABLE QVariantList getBooksForChallenge(int challengeId);

    Q_INVOKABLE bool exportToCsv(const QString &filePath);
    Q_INVOKABLE int  importFromCsv(const QString &filePath);
    Q_INVOKABLE bool resetAllData();

    QString filterStatus() const;
    void setFilterStatus(const QString &status);
    QString searchQuery() const;
    void setSearchQuery(const QString &query);
    int filterYear() const;
    void setFilterYear(int year);
    QString filterYearMode() const;
    void setFilterYearMode(const QString &mode);
    QString sortMode() const;
    void setSortMode(const QString &mode);

signals:
    void filterStatusChanged();
    void searchQueryChanged();
    void filterYearChanged();
    void filterYearModeChanged();
    void sortModeChanged();
    void booksChanged();
    void errorOccurred(const QString &message);

private:
    void applyFilters();
    void sortBooks(QVector<Book> &books);

    BookModel *m_model;
    QVector<Book> m_allBooks;
    QString m_filterStatus;
    QString m_searchQuery;
    int m_filterYear = 0;
    QString m_filterYearMode = QStringLiteral("finish");
    QString m_sortMode = QStringLiteral("default");
};
