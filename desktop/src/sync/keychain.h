#pragma once

#include <QString>

#include <functional>

/**
 * Secret storage backed by the macOS Keychain.
 *
 * Tokens must not go in QSettings. On macOS that is a plist in the user's
 * Library, world-readable within the account and trivially recovered from a
 * backup or a synced Preferences folder. A refresh token lives for thirty days
 * and grants full access to the library, so it belongs where the operating
 * system already guards credentials.
 *
 * The functions are free rather than a class: there is no state to hold, and
 * the Keychain itself is the storage.
 *
 * ── Every call here may block, possibly for a long time ─────────────────────
 *
 * A Keychain item may normally be used without ceremony only by the program
 * that created it; anyone else gets a system panel asking the user to allow it,
 * and the call does not return until somebody answers. That rule assumes a
 * stable code signature. This application is built locally and its signature is
 * the one the linker emits — ad-hoc, with no bound Info.plist and no designated
 * requirement — so macOS cannot record a durable grant, and the panel comes
 * back on its own schedule. The observed symptom was a working session that
 * stopped working after a day away, with the log saying only "Sign in required"
 * and no way out but retyping the server password.
 *
 * Refusing the panel outright, which is what this file used to do, turned the
 * hang into an immediate failure — and into that password prompt. Answering it
 * once with "Always Allow" is a far better trade, so interaction is permitted
 * again, and the blocking is dealt with by never being on the main thread.
 *
 * @warning Call retrieve/store/remove only from a worker thread, or through
 *   runSerial(), which provides one. On the main thread a panel freezes the
 *   interface, and during QML construction it freezes the application so
 *   thoroughly that no window ever appears — a stack trace caught exactly that,
 *   parked inside SecItemCopyMatching.
 */
namespace BookWorm::Keychain {

/**
 * Store or replace a secret. Blocking — see the warning above.
 *
 * @param account identifies the entry within the BookWorm service, e.g. the
 *   email the token belongs to, so two accounts do not overwrite each other.
 */
bool store(const QString &account, const QString &key, const QString &secret);

/** @returns the secret, or an empty string when there is none. Blocking. */
QString retrieve(const QString &account, const QString &key);

/** Removing an entry that does not exist is success, not failure. Blocking. */
bool remove(const QString &account, const QString &key);

/**
 * Run @p job on the one Keychain worker thread.
 *
 * One thread, not one per call, and that is the point rather than an economy.
 * Writes have to keep their order: a rotation stores a new refresh token while
 * the previous store may still be waiting on a panel, and if the older write
 * lands second the item holds a token the server has already retired. Serialising
 * also means at most one system panel is ever up, instead of a stack of them.
 */
void runSerial(std::function<void()> job);

/**
 * Wait for queued work to finish, up to @p timeoutMs.
 *
 * Called at shutdown. A rotation is only durable once its token has been
 * written, so exiting with the queue non-empty is how a session gets lost —
 * the server has retired the old token and this machine never recorded the new
 * one. Bounded, because a window that will not close is worse: a panel nobody
 * answers must not hold the application open.
 *
 * @returns false when the timeout was reached with work outstanding.
 */
bool flush(int timeoutMs);

} // namespace BookWorm::Keychain
