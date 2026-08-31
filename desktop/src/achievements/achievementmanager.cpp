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
}

void AchievementManager::loadUnlocked()
{
    m_unlocked.clear();

    QSqlQuery q(DatabaseManager::instance().database());
    if (!q.exec(QStringLiteral("SELECT key, unlocked_at FROM achievements_unlocked"))) {
        qWarning() << "achievements: cannot read unlocks:" << q.lastError().text();
        return;
    }

    while (q.next())
        m_unlocked.insert(q.value(0).toString(), q.value(1).toDateTime().toString(Qt::ISODate));
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

bool AchievementManager::persist(const QString &key)
{
    QSqlQuery q(DatabaseManager::instance().database());
    q.prepare(QStringLiteral(
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
        if (persist(def.key))
            ++seeded;
    }

    persist(SEED_MARKER);
    loadUnlocked();

    if (seeded > 0)
        qInfo() << "achievements: recorded" << seeded << "already earned";

    emit changed();
}

void AchievementManager::recheck()
{
    const QHash<Metric, int> values = measure();

    QVector<const Definition *> fresh;
    for (const Definition &def : BookWorm::Achievements::catalog()) {
        if (m_unlocked.contains(def.key))
            continue;
        if (values.value(def.metric) < def.threshold)
            continue;
        // persist() decides, not the in-memory set: it is the write that says
        // this is the first time, and it says so atomically.
        if (persist(def.key))
            fresh.append(&def);
    }

    if (fresh.isEmpty())
        return;

    loadUnlocked();
    emit changed();

    for (const Definition *def : fresh) {
        // Logged as well as shown. A notification is gone in four seconds, so
        // when somebody asks whether one actually fired, the panel is not
        // available to be asked.
        qInfo() << "achievements: unlocked" << def->key;
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

        QVariantMap row;
        row[QStringLiteral("key")] = def.key;
        row[QStringLiteral("title")] = def.title;
        row[QStringLiteral("description")] = def.description;
        row[QStringLiteral("icon")] = def.icon;
        row[QStringLiteral("unlocked")] = isUnlocked;
        row[QStringLiteral("unlockedAt")] = m_unlocked.value(def.key);
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
