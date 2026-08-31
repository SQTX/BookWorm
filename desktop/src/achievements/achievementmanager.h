#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

#include "achievementcatalog.h"

/**
 * Decides what has been earned, remembers it, and says so once.
 *
 * The interesting requirement is the "once". An achievement is a moment, and a
 * moment that reappears every time the application starts is not a moment — so
 * the unlock is a row in the database, written the first time the threshold is
 * met and never written again. Everything else here follows from that.
 *
 * Earning and announcing are separate, and the row records both times. Being
 * earned is a fact about the library; being announced is a fact about this
 * screen, and the two come apart constantly — a book finished on the phone is
 * earned while the desktop is closed, and there is nobody here to tell. So an
 * unlock is written with no shown time, and everything still unannounced is
 * presented at the next opportunity, oldest first. Three things fall out of
 * that, all of them wanted: a backlog earned elsewhere arrives in the order it
 * was earned rather than all at once in catalogue order; an application killed
 * mid-notification has not consumed it, so it appears next launch instead of
 * being lost; and "has the user actually seen this" becomes a question the
 * database can answer.
 *
 * Nothing is ever taken away. Deleting a book can drop the library count back
 * below a threshold, and the achievement stays: it was earned, and quietly
 * retracting it would be a worse answer than a count that no longer matches.
 * That is also why every metric in the catalogue is one that only grows in
 * ordinary use — the rule needs no exceptions.
 *
 * Local by design, and not synced. The phone and the desktop read the same
 * library and will unlock the same things from it on their own, so putting
 * achievements on the wire would add an entity to the sync protocol to
 * reproduce a result both sides already reach independently.
 */
class AchievementManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int unlockedCount READ unlockedCount NOTIFY changed)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY changed)

public:
    explicit AchievementManager(QObject *parent = nullptr);

    int unlockedCount() const { return m_unlocked.size(); }
    int totalCount() const { return BookWorm::Achievements::catalog().size(); }

    /**
     * Every achievement, earned or not, for the browse view.
     *
     * Each entry carries `key`, `title`, `description`, `icon`, `unlocked`,
     * `unlockedAt`, `current`, `target` and `progress` (0–1). The locked ones
     * are the point: an achievement nobody can see the shape of is not a goal,
     * it is a surprise.
     */
    Q_INVOKABLE QVariantList entries() const;

    /**
     * Re-measure, record anything newly earned, then announce the backlog.
     *
     * Cheap enough to call on every change to the library — it is a handful of
     * aggregate queries — and that is how it is wired, because an achievement
     * that arrives on the next launch instead of at the moment it was earned
     * has missed its only job. Also called once at startup, which is what
     * collects whatever was earned while this machine was not running.
     */
    Q_INVOKABLE void recheck();

    /**
     * Fire a notification for an achievement that does not exist.
     *
     * Scaffolding, and the only way to see the panel on demand: every real
     * achievement announces itself once and then never again, which is correct
     * and also means there is no way to look at the thing twice. This writes
     * nothing, is not in the catalogue, and does not appear in the browse view —
     * it only pushes one entry through the same notification path the real ones
     * use, so what you are looking at is the real panel.
     *
     * TEMPORARY. Two lines to remove: this method, and the Component.onCompleted
     * in AchievementsView.qml that calls it.
     */
    Q_INVOKABLE void demoUnlock();

signals:
    /** Show this one. Emitted once per achievement, ever. */
    void unlocked(const QString &key, const QString &title,
                  const QString &description, const QString &icon);

    void changed();

private:
    void ensureSchema();
    void loadUnlocked();

    /**
     * Emit every unlock that has not been shown yet, oldest first, and mark
     * them shown.
     *
     * Ordered by when it was earned, then by catalogue order to break a tie —
     * several achievements detected in one pass share a timestamp, and within
     * a family the catalogue is already in ascending order, so ten books
     * announces after five rather than beside it.
     *
     * The honest limit: `unlocked_at` is when *this machine first noticed*, not
     * when the reading happened. Achievements are computed from the library's
     * current state, and a state does not remember the order it was reached in,
     * so a backlog earned on the phone across a week arrives stamped with the
     * moment the desktop caught up. The order within it is the best the data
     * supports.
     */
    void announcePending();

    /** Current value of every metric, from one pass of aggregate queries. */
    QHash<BookWorm::Achievements::Metric, int> measure() const;

    /**
     * Write the achievements already earned, without announcing them.
     *
     * Runs once, on the first launch that has this feature. A library of a
     * hundred books satisfies most of the catalogue immediately, and the first
     * thing the user would otherwise see is thirty notifications queued behind
     * each other for things they did over several years. Those are history, not
     * events. After the marker is written, every later unlock is a real one and
     * is announced.
     */
    void seedSilently();

    /**
     * Record an unlock. @returns false when it was already recorded.
     *
     * @param alreadySeen stamps the shown time too, which suppresses the
     *   notification. Only seeding wants that.
     */
    bool persist(const QString &key, bool alreadySeen = false);

    struct Record {
        QString unlockedAt;   ///< ISO 8601. When this machine first saw it earned.
        QString shownAt;      ///< ISO 8601, empty while it is still waiting to be shown.
    };

    QHash<QString, Record> m_unlocked;
};
