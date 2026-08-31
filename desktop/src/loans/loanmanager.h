#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

/**
 * Who has your books, and whose books you have.
 *
 * A loan is a row with two dates: the day it left, and the day it came back.
 * Open loans are the ones with no return date, and they are the entire point —
 * a book lent and forgotten is a book lost, and the only thing standing between
 * those two is a note of who took it.
 *
 * Deliberately **not** a book status. A lent book is still read, or still being
 * read, and the two facts are independent: making "lent" a fifth status would
 * force every filter, sort and statistic in the application to decide what it
 * means, and would lose the reading state the moment the book went out.
 *
 * Local to this machine, like achievements and unlike books — but for a
 * different reason. Achievements are recomputable from the library, so syncing
 * them would duplicate work both clients already do; a loan is primary data
 * that exists nowhere else. What makes local storage safe here is the ZIP
 * backup, which captures the whole database, and the fact that the phone
 * application only moves page counts and has nowhere to show this.
 */
class LoanManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int lentOutCount READ lentOutCount NOTIFY changed)
    Q_PROPERTY(int borrowedCount READ borrowedCount NOTIFY changed)

public:
    explicit LoanManager(QObject *parent = nullptr);

    int lentOutCount() const;
    int borrowedCount() const;

    /**
     * Open a loan. @p direction is "lent" (you gave it away) or "borrowed"
     * (it is not yours).
     *
     * @returns false when the book already has an open loan. One book cannot be
     *   in two places, and the database enforces it as well — a partial unique
     *   index rather than a check here, so a second window or a stale dialog
     *   cannot slip past the moment between reading and writing.
     */
    Q_INVOKABLE bool startLoan(int bookId, const QString &direction,
                               const QString &counterparty, const QString &isoDate,
                               const QString &note);

    /** Close a loan by recording the day it came back. */
    Q_INVOKABLE bool endLoan(int loanId, const QString &isoDate);

    /** Remove a loan outright — for one entered by mistake. */
    Q_INVOKABLE bool deleteLoan(int loanId);

    /** Every open loan, both directions, oldest first. */
    Q_INVOKABLE QVariantList openLoans() const;

    /** Loans that have come back, most recently returned first. */
    Q_INVOKABLE QVariantList history() const;

    /** Every loan for one book, newest first — its lending record. */
    Q_INVOKABLE QVariantList forBook(int bookId) const;

    /** The open loan on this book, or an empty map. */
    Q_INVOKABLE QVariantMap openLoanFor(int bookId) const;

    /**
     * Who currently holds @p bookId, or an empty string.
     *
     * A hash lookup rather than a query, because the library grid asks once per
     * card: on a hundred books a query per delegate is a hundred round trips
     * every time the view is rebuilt. The map is refilled whenever a loan
     * changes, which is the only thing that can alter the answer.
     */
    Q_INVOKABLE QString holderOf(int bookId) const;

    /** True when this book is out on loan in either direction. */
    Q_INVOKABLE bool isOnLoan(int bookId) const { return m_open.contains(bookId); }

    /** Names already used, for completing the field rather than retyping. */
    Q_INVOKABLE QStringList people() const;

signals:
    /** A loan was opened, closed or removed. */
    void changed();

private:
    void ensureSchema();
    void refreshOpen();

    /** Shared shape for openLoans/history/forBook, so the three cannot drift. */
    QVariantList query(const QString &where, const QString &order,
                       const QVariantList &binds = {}) const;

    struct Open {
        QString counterparty;
        QString direction;
    };

    /** bookId → its open loan. Mirrors the rows with no return date. */
    QHash<int, Open> m_open;
};
