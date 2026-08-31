#include "achievementmanager.h"

#include "../database/databasemanager.h"

#include <QDebug>
#include <QSqlError>
#include <QSqlQuery>
#include <QVariantMap>

using BookWorm::Achievements::Definition;
using BookWorm::Achievements::Metric;

namespace {

/**
 * The row that marks the catalogue as having been seeded.
 *
 * Stored in the same table as the achievements, under a key no achievement can
 * have — a separate table for one boolean would be a heavier thing to migrate
 * and to back up. The leading underscores keep it out of the browse view, which
 * only ever looks up keys the catalogue names.
 */
const QString SEED_MARKER = QStringLiteral("__seeded__");

/** @returns the single integer a scalar aggregate produced, or 0. */
int scalar(QSqlQuery &q)
{
    if (!q.next())
        return 0;
    return q.value(0).toInt();
}

} // namespace

AchievementManager::AchievementManager(QObject *parent)
    : QObject(parent)
{
    ensureSchema();
    loadUnlocked();

    if (!m_unlocked.contains(SEED_MARKER))
        seedSilently();
}

void AchievementManager::ensureSchema()
{
    QSqlQuery q(DatabaseManager::instance().database());

    // The key is the primary key rather than a serial: the catalogue names it,
    // it never changes, and making it the identity is what makes recording an
    // unlock idempotent without a prior read.
    if (!q.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS achievements_unlocked ("
            "  key VARCHAR(64) PRIMARY KEY,"
            "  unlocked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()"
            ")"))) {
        qWarning() << "achievements: cannot create table:" << q.lastError().text();
    }

    // NULL means earned but not yet put in front of the user.
    //
    // Whether the column already exists is asked explicitly rather than handled
    // with ADD COLUMN IF NOT EXISTS, because the backfill below must run once —
    // at the moment of the upgrade — and never again. An earlier attempt used a
    // time window instead ("anything older than an hour was surely already
    // shown"), which is wrong in the one case this feature exists for: an
    // achievement earned on the phone yesterday is a genuine backlog, and the
    // window silently ate it. A test caught it doing exactly that.
    const bool hasShownAt = q.exec(QStringLiteral(
            "SELECT 1 FROM information_schema.columns "
            " WHERE table_name = 'achievements_unlocked' AND column_name = 'shown_at'"))
        && q.next();

    if (hasShownAt)
        return;

    if (!q.exec(QStringLiteral(
            "ALTER TABLE achievements_unlocked "
            "  ADD COLUMN shown_at TIMESTAMP WITH TIME ZONE"))) {
        qWarning() << "achievements: cannot add shown_at:" << q.lastError().text();
        return;
    }

    // Every row that existed before this column did was announced under the old
    // rule, which showed it and recorded nothing. Marking them seen is the only
    // reading that does not replay years of history at the next launch.
    if (!q.exec(QStringLiteral(
            "UPDATE achievements_unlocked SET shown_at = unlocked_at WHERE shown_at IS NULL"))) {
        qWarning() << "achievements: cannot backfill shown_at:" << q.lastError().text();
    }
}

void AchievementManager::loadUnlocked()
{
    m_unlocked.clear();

    QSqlQuery q(DatabaseManager::instance().database());
    if (!q.exec(QStringLiteral("SELECT key, unlocked_at, shown_at FROM achievements_unlocked"))) {
        qWarning() << "achievements: cannot read unlocks:" << q.lastError().text();
        return;
    }

    while (q.next()) {
        Record record;
        record.unlockedAt = q.value(1).toDateTime().toString(Qt::ISODate);
        // Null stays an empty string rather than becoming an epoch date, so
        // "never shown" is distinguishable from "shown in 1970".
        if (!q.value(2).isNull())
            record.shownAt = q.value(2).toDateTime().toString(Qt::ISODate);
        m_unlocked.insert(q.value(0).toString(), record);
    }
}

QHash<Metric, int> AchievementManager::measure() const
{
    QHash<Metric, int> values;
    QSqlQuery q(DatabaseManager::instance().database());

    q.exec(QStringLiteral("SELECT COUNT(*) FROM books"));
    values[Metric::LibrarySize] = scalar(q);

    q.exec(QStringLiteral("SELECT COUNT(*) FROM books WHERE status = 'read'"));
    values[Metric::BooksRead] = scalar(q);

    // EXTRACT on end_date, not on created_at: a book entered today and finished
    // two years ago belongs to the year it was read.
    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM books "
        " WHERE status = 'read' AND end_date IS NOT NULL "
        "   AND EXTRACT(YEAR FROM end_date) = EXTRACT(YEAR FROM CURRENT_DATE)"));
    values[Metric::BooksReadThisYear] = scalar(q);

    q.exec(QStringLiteral(
        "SELECT COALESCE(SUM(page_count), 0) FROM books "
        " WHERE status = 'read' AND page_count IS NOT NULL"));
    values[Metric::PagesRead] = scalar(q);

    // A series counts only with more than one book in it. A one-book "series"
    // would otherwise make "finish every book in a series" fire on any book
    // that happened to have the field filled in, which is not the achievement.
    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM ("
        "  SELECT series FROM books"
        "   WHERE series IS NOT NULL AND series <> ''"
        "   GROUP BY series"
        "  HAVING COUNT(*) > 1 AND COUNT(*) FILTER (WHERE status = 'read') = COUNT(*)"
        ") s"));
    values[Metric::SeriesCompleted] = scalar(q);

    q.exec(QStringLiteral(
        "SELECT COUNT(DISTINCT genre) FROM books "
        " WHERE status = 'read' AND genre IS NOT NULL AND genre <> ''"));
    values[Metric::GenresRead] = scalar(q);

    // Gaps and islands. Consecutive dates advance in step with the row number,
    // so date minus row number is constant within a run and changes at every
    // gap; grouping on that difference gives one group per run. DISTINCT first,
    // because two sessions on one day are one reading day.
    q.exec(QStringLiteral(
        "SELECT COALESCE(MAX(len), 0) FROM ("
        "  SELECT COUNT(*) AS len FROM ("
        "    SELECT session_date,"
        "           session_date - (ROW_NUMBER() OVER (ORDER BY session_date))::int AS run"
        "      FROM (SELECT DISTINCT session_date FROM reading_sessions) d"
        "  ) g GROUP BY run"
        ") runs"));
    values[Metric::LongestStreak] = scalar(q);

    // read_count is 1 for a book read once, so a reread is every count past the
    // first. GREATEST guards the rows backfilled before the column existed.
    q.exec(QStringLiteral(
        "SELECT COALESCE(SUM(GREATEST(read_count - 1, 0)), 0) FROM books"));
    values[Metric::Rereads] = scalar(q);

    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM books WHERE status = 'read' AND rating IS NOT NULL"));
    values[Metric::BooksRated] = scalar(q);

    q.exec(QStringLiteral(
        "SELECT (SELECT COUNT(*) FROM favorite_quotes)"
        "     + (SELECT COUNT(*) FROM highlights)"));
    values[Metric::NotesTaken] = scalar(q);

    return values;
}

bool AchievementManager::persist(const QString &key, bool alreadySeen)
{
    QSqlQuery q(DatabaseManager::instance().database());
    q.prepare(alreadySeen
        ? QStringLiteral(
              "INSERT INTO achievements_unlocked (key, shown_at) VALUES (:key, NOW()) "
              "ON CONFLICT (key) DO NOTHING")
        : QStringLiteral(
              "INSERT INTO achievements_unlocked (key) VALUES (:key) "
              "ON CONFLICT (key) DO NOTHING"));
    q.bindValue(QStringLiteral(":key"), key);

    if (!q.exec()) {
        qWarning() << "achievements: cannot record" << key << q.lastError().text();
        return false;
    }

    // The conflict clause is what makes this the single source of truth for
    // "has this been announced". Two callers racing, or a recheck arriving
    // twice, cannot produce two notifications for one achievement.
    return q.numRowsAffected() > 0;
}

void AchievementManager::seedSilently()
{
    const QHash<Metric, int> values = measure();

    int seeded = 0;
    for (const Definition &def : BookWorm::Achievements::catalog()) {
        if (values.value(def.metric) < def.threshold)
            continue;
        // Stamped as shown: these are history, not events, and announcing them
        // is the thing this whole function exists to avoid.
        if (persist(def.key, /*alreadySeen=*/true))
            ++seeded;
    }

    persist(SEED_MARKER, /*alreadySeen=*/true);
    loadUnlocked();

    if (seeded > 0)
        qInfo() << "achievements: recorded" << seeded << "already earned";

    emit changed();
}

void AchievementManager::recheck()
{
    const QHash<Metric, int> values = measure();

    int fresh = 0;
    for (const Definition &def : BookWorm::Achievements::catalog()) {
        if (m_unlocked.contains(def.key))
            continue;
        if (values.value(def.metric) < def.threshold)
            continue;
        // persist() decides, not the in-memory set: it is the write that says
        // this is the first time, and it says so atomically.
        if (persist(def.key))
            ++fresh;
    }

    if (fresh > 0) {
        loadUnlocked();
        emit changed();
    }

    // Unconditionally, even when nothing new was found. What is waiting to be
    // shown is not the same question as what was just earned: a backlog from
    // the phone was recorded by an earlier pass, and a notification interrupted
    // by a crash was never consumed. Both are still owed to the user.
    announcePending();
}

void AchievementManager::announcePending()
{
    QSqlQuery q(DatabaseManager::instance().database());
    if (!q.exec(QStringLiteral(
            "SELECT key FROM achievements_unlocked "
            " WHERE shown_at IS NULL ORDER BY unlocked_at, key"))) {
        qWarning() << "achievements: cannot read the backlog:" << q.lastError().text();
        return;
    }

    QStringList pending;
    while (q.next())
        pending.append(q.value(0).toString());

    if (pending.isEmpty())
        return;

    // Catalogue order breaks a tie, and the ties are the common case: several
    // achievements detected in one pass share a timestamp to the microsecond.
    // Within a family the catalogue ascends, so ten books follows five instead
    // of landing beside it in whatever order the key sorted.
    const QVector<Definition> &all = BookWorm::Achievements::catalog();
    QVector<const Definition *> ordered;
    for (const QString &key : pending) {
        for (const Definition &def : all) {
            if (def.key == key) {
                ordered.append(&def);
                break;
            }
        }
        // A key with no definition is the seed marker, or an achievement
        // retired from a later build. Skipped, and still marked shown below, so
        // it cannot sit in the backlog for ever.
    }

    QSqlQuery mark(DatabaseManager::instance().database());
    mark.prepare(QStringLiteral(
        "UPDATE achievements_unlocked SET shown_at = NOW() WHERE shown_at IS NULL"));
    if (!mark.exec()) {
        // Not shown at all rather than shown and forgotten. Emitting first and
        // failing to record it would replay the same notifications at every
        // launch, which is worse than showing them one launch late.
        qWarning() << "achievements: cannot mark as shown, holding them back:"
                   << mark.lastError().text();
        return;
    }

    loadUnlocked();
    emit changed();

    for (const Definition *def : ordered) {
        // Logged as well as shown. A notification is gone in four seconds, so
        // when somebody asks whether one actually fired, the panel is no longer
        // available to be asked.
        qInfo() << "achievements: showing" << def->key;
        emit unlocked(def->key, def->title, def->description, def->icon);
    }
}

void AchievementManager::demoUnlock()
{
    // Deliberately not persisted and deliberately not in the catalogue: it must
    // be repeatable to be useful, and anything that both repeats and is recorded
    // would be a second unlock rule to reason about.
    emit unlocked(QStringLiteral("__demo__"),
                  QStringLiteral("Test Achievement"),
                  QStringLiteral("Fires every time this page opens — for testing the panel"),
                  QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/placeholder.jpg"));
}

QVariantList AchievementManager::entries() const
{
    const QHash<Metric, int> values = measure();

    QVariantList out;
    out.reserve(BookWorm::Achievements::catalog().size());

    for (const Definition &def : BookWorm::Achievements::catalog()) {
        const int current = values.value(def.metric);
        const bool isUnlocked = m_unlocked.contains(def.key);
        const Record record = m_unlocked.value(def.key);

        QVariantMap row;
        row[QStringLiteral("key")] = def.key;
        row[QStringLiteral("title")] = def.title;
        row[QStringLiteral("description")] = def.description;
        row[QStringLiteral("icon")] = def.icon;
        row[QStringLiteral("unlocked")] = isUnlocked;
        row[QStringLiteral("unlockedAt")] = record.unlockedAt;
        row[QStringLiteral("shownAt")] = record.shownAt;
        // Earned, but the notification for it has not run yet — the state a
        // backlog from another device sits in until this application opens.
        row[QStringLiteral("pending")] = isUnlocked && record.shownAt.isEmpty();
        // Clamped, and reported as earned once it is earned: a book deleted
        // after the fact must not show a completed achievement at 80%.
        row[QStringLiteral("current")] = isUnlocked ? qMax(current, def.threshold) : current;
        row[QStringLiteral("target")] = def.threshold;
        row[QStringLiteral("progress")] =
            isUnlocked ? 1.0
                       : qBound(0.0, double(current) / double(def.threshold), 1.0);
        out.append(row);
    }

    return out;
}
