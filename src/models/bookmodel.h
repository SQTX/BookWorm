#pragma once

#include <QAbstractListModel>
#include <QQmlEngine>
#include "book.h"

class BookModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum BookRoles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        AuthorRole,
        GenreRole,
        PageCountRole,
        StartDateRole,
        EndDateRole,
        RatingRole,
        StatusRole,
        NotesRole,
        IsbnRole,
        PublisherRole,
        PublicationYearRole,
        PublicationDateRole,
        LanguageRole,
        CoverImagePathRole,
        ItemTypeRole,
        IsNonFictionRole,
        CurrentPageRole,
        SeriesRole,
        TagsRole
    };

    explicit BookModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setBooks(const QVector<Book> &books);
    void addBook(const Book &book);
    void updateBook(const Book &book);
    void removeBook(int id);

    int count() const;

signals:
    void countChanged();

private:
    QVector<Book> m_books;
};
