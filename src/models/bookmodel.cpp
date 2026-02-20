#include "bookmodel.h"

BookModel::BookModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int BookModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_books.size();
}

QVariant BookModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_books.size())
        return {};

    const Book &book = m_books.at(index.row());

    switch (role) {
    case IdRole:              return book.id;
    case TitleRole:           return book.title;
    case AuthorRole:          return book.author;
    case GenreRole:           return book.genre;
    case PageCountRole:       return book.pageCount;
    case StartDateRole:       return book.startDate.isValid() ? book.startDate.toString(Qt::ISODate) : QString();
    case EndDateRole:         return book.endDate.isValid() ? book.endDate.toString(Qt::ISODate) : QString();
    case RatingRole:          return book.rating;
    case StatusRole:          return book.status;
    case NotesRole:           return book.notes;
    case IsbnRole:            return book.isbn;
    case PublisherRole:       return book.publisher;
    case PublicationYearRole: return book.publicationYear;
    case LanguageRole:        return book.language;
    case CoverImagePathRole:  return book.coverImagePath;
    case ItemTypeRole:        return book.itemType;
    case IsNonFictionRole:    return book.isNonFiction;
    case TagsRole:            return book.tags.join(", ");
    }

    return {};
}

QHash<int, QByteArray> BookModel::roleNames() const
{
    return {
        { IdRole,              "bookId" },
        { TitleRole,           "title" },
        { AuthorRole,          "author" },
        { GenreRole,           "genre" },
        { PageCountRole,       "pageCount" },
        { StartDateRole,       "startDate" },
        { EndDateRole,         "endDate" },
        { RatingRole,          "rating" },
        { StatusRole,          "status" },
        { NotesRole,           "notes" },
        { IsbnRole,            "isbn" },
        { PublisherRole,       "publisher" },
        { PublicationYearRole, "publicationYear" },
        { LanguageRole,        "language" },
        { CoverImagePathRole,  "coverImagePath" },
        { ItemTypeRole,        "itemType" },
        { IsNonFictionRole,    "isNonFiction" },
        { TagsRole,            "tags" }
    };
}

void BookModel::setBooks(const QVector<Book> &books)
{
    beginResetModel();
    m_books = books;
    endResetModel();
    emit countChanged();
}

void BookModel::addBook(const Book &book)
{
    beginInsertRows(QModelIndex(), 0, 0);
    m_books.prepend(book);
    endInsertRows();
    emit countChanged();
}

void BookModel::updateBook(const Book &book)
{
    for (int i = 0; i < m_books.size(); ++i) {
        if (m_books[i].id == book.id) {
            m_books[i] = book;
            emit dataChanged(index(i), index(i));
            return;
        }
    }
}

void BookModel::removeBook(int id)
{
    for (int i = 0; i < m_books.size(); ++i) {
        if (m_books[i].id == id) {
            beginRemoveRows(QModelIndex(), i, i);
            m_books.removeAt(i);
            endRemoveRows();
            emit countChanged();
            return;
        }
    }
}

int BookModel::count() const
{
    return m_books.size();
}
