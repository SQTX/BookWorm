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

public:
    explicit BookController(QObject *parent = nullptr);

    BookModel *model() const;

    Q_INVOKABLE void loadBooks();
    Q_INVOKABLE bool addBook(const QVariantMap &bookData);
    Q_INVOKABLE bool updateBook(const QVariantMap &bookData);
    Q_INVOKABLE bool deleteBook(int id);
    Q_INVOKABLE QVariantMap getBookDetails(int id);

    Q_INVOKABLE QStringList getAllTags();

    Q_INVOKABLE bool addQuote(int bookId, const QString &quote, int page);
    Q_INVOKABLE bool removeQuote(int quoteId);
    Q_INVOKABLE QVariantList getQuotesForBook(int bookId);

    Q_INVOKABLE bool exportToCsv(const QString &filePath);
    Q_INVOKABLE int  importFromCsv(const QString &filePath);

    QString filterStatus() const;
    void setFilterStatus(const QString &status);
    QString searchQuery() const;
    void setSearchQuery(const QString &query);

signals:
    void filterStatusChanged();
    void searchQueryChanged();
    void booksChanged();
    void errorOccurred(const QString &message);

private:
    void applyFilters();

    BookModel *m_model;
    QVector<Book> m_allBooks;
    QString m_filterStatus;
    QString m_searchQuery;
};
