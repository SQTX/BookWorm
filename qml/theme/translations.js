.pragma library

var _pl = {
    // ── Settings dialog (rebuilt UI) ──
    "General": "Ogólne",
    "Appearance": "Wygląd",
    "Backup": "Kopia zapasowa",
    "Data": "Dane",
    "Restore": "Przywracanie",
    "Language": "Język",
    "The interface language changes immediately — no restart needed.":
        "Język interfejsu zmienia się od razu — restart nie jest potrzebny.",
    "Library layout": "Układ biblioteki",
    "Fitted to the window width": "Dopasowane do szerokości okna",
    "Fixed number of columns": "Stała liczba kolumn",
    "Flagged books get their own section on top":
        "Oznaczone książki dostają własną sekcję na górze",
    "Flagged books on top": "Oznaczone książki na górze",
    "Backup folder": "Folder kopii zapasowych",
    "Change": "Zmień",
    "Checked once at every app start": "Sprawdzane raz przy każdym starcie aplikacji",
    "Days": "Dni",
    "Months": "Miesiące",
    "Years": "Lata",
    "A backup is a ZIP with the full database, every cover image and a manifest. CSV export is not a backup.":
        "Kopia zapasowa to ZIP z pełną bazą danych, wszystkimi okładkami i manifestem. Eksport CSV to nie jest kopia zapasowa.",
    "Restoring replaces your entire library with the contents of an archive. A safety backup is taken first.":
        "Przywracanie zastępuje całą bibliotekę zawartością archiwum. Najpierw tworzona jest kopia bezpieczeństwa.",
    "Import and export": "Import i eksport",
    "Danger zone": "Strefa ryzyka",
    "Import": "Importuj",
    "Export": "Eksportuj",
    "Books and their fields as a spreadsheet. Quotes, highlights and sessions are not included.":
        "Książki i ich pola jako arkusz. Bez cytatów, zaznaczeń i sesji czytania.",
    "Add books from a CSV file. Existing books are kept.":
        "Dodaje książki z pliku CSV. Istniejące książki zostają zachowane.",
    "Quotes, highlights, summaries and reviews for the whole library in one file.":
        "Cytaty, zaznaczenia, streszczenia i recenzje z całej biblioteki w jednym pliku.",
    "Deletes every book, tag, quote, challenge and reading session. This cannot be undone.":
        "Usuwa każdą książkę, tag, cytat, wyzwanie i sesję czytania. Operacja jest nieodwracalna.",
    "Reset": "Wyczyść",
    "Changes are saved as you make them": "Zmiany zapisują się na bieżąco",

    // ── Empty states ──
    "Your library is empty": "Twoja biblioteka jest pusta",
    "Add your first book to start tracking what you read.":
        "Dodaj pierwszą książkę, aby zacząć śledzić swoje czytanie.",
    "Try a different search term, or clear the filters.":
        "Spróbuj innej frazy albo wyczyść filtry.",
    "Clear filters": "Wyczyść filtry",
    "Add Book": "Dodaj książkę",
    "Fill in the Series field on a book and it will show up here, grouped with the rest of its cycle.":
        "Uzupełnij pole Seria przy książce, a pojawi się tutaj razem z resztą cyklu.",
    "No challenges yet": "Brak wyzwań",
    "New challenge": "Nowe wyzwanie",
    "Set a target — books, pages, or pages per day — and a deadline, and track how you are doing against it.":
        "Ustaw cel — książki, strony lub strony dziennie — oraz termin, i śledź swoje postępy.",
    "active": "aktywne",
    "completed": "ukończone",

    // ── Navigation ──
    "Library": "Biblioteka",
    "Table": "Tabela",
    "Statistics": "Statystyki",
    "Challenges": "Wyzwania",

    // ── Settings ──
    "Settings": "Ustawienia",
    "Tags": "Tagi",
    "Export CSV": "Eksportuj CSV",
    "Import CSV": "Importuj CSV",
    "LANGUAGE": "JĘZYK",
    "APP STYLE": "STYL APLIKACJI",
    "Minimalist Light": "Minimalistyczny jasny",
    "Minimalist Dark": "Minimalistyczny ciemny",
    "Classic": "Klasyczny",
    // ── Backup ──
    "BACKUP": "KOPIA ZAPASOWA",
    "Back Up Now": "Wykonaj kopię",
    "Save Backup": "Zapisz kopię zapasową",
    "Choose Backup Folder": "Wybierz folder kopii",
    "No folder chosen": "Nie wybrano folderu",
    "Automatic backup": "Kopia automatyczna",
    "Choose a folder to enable automatic backup": "Wskaż folder, aby włączyć kopie automatyczne",
    "Every": "Co",
    "Last backup": "Ostatnia kopia",
    "No backup yet": "Brak kopii",
    "pg_dump not found — backup unavailable": "Nie znaleziono pg_dump — kopia niedostępna",

    // ── Restore ──
    "Restore from Backup": "Przywróć z kopii",
    "psql not found — restore unavailable": "Nie znaleziono psql — przywracanie niedostępne",
    "Restore replaces everything": "Przywracanie zastąpi wszystko",
    "Every book currently in your library will be permanently replaced by the contents of this archive. This action cannot be undone.":
        "Każda książka w Twojej bibliotece zostanie trwale zastąpiona zawartością tej kopii. Ta operacja jest nieodwracalna.",
    "Books now": "Książek teraz",
    "Books in archive": "Książek w kopii",
    "Safety backup will be written to": "Kopia bezpieczeństwa trafi do",
    "Type %1 to confirm": "Wpisz %1, aby potwierdzić",
    "RESTORE": "ODTWÓRZ",
    "Restoring…": "Przywracanie…",
    "Restore failed": "Przywracanie nie powiodło się",
    "Safety backup path": "Ścieżka kopii bezpieczeństwa",
    "Copy": "Kopiuj",
    "Close": "Zamknij",

    "Reset All Data": "Resetuj dane",
    "Reset Data": "Resetowanie danych",
    "Are you sure you want to delete all data? This action cannot be undone.":
        "Czy na pewno chcesz usunąć wszystkie dane? Ta operacja jest nieodwracalna.",
    "Cancel": "Anuluj",
    "All data has been reset": "Dane zostały zresetowane",

    // ── CSV dialogs ──
    "Export to CSV": "Eksportuj do CSV",
    "Import from CSV": "Importuj z CSV",
    "Export completed successfully": "Eksport zakończony pomyślnie",
    "Export failed": "Błąd eksportu",
    "Import failed": "Błąd importu",
    "Imported": "Zaimportowano",

    // ── Tags popup ──
    "No tags yet": "Brak tagów",
    "New tag...": "Nowy tag...",
    "Pick color": "Wybierz kolor",

    // ── Status labels ──
    "Reading": "W trakcie",
    "Read": "Przeczytane",
    "Planned": "Planowane",
    "Abandoned": "Porzucone",
    "All": "Wszystkie",

    // ── BookListView / BookTableView ──
    "Search title / author...": "Szukaj tytuł / autor...",
    "Start": "Początek",
    "Finish": "Koniec",
    "Layout": "Układ",
    "Auto": "Auto",
    "Cards per row": "Karty w rzędzie",
    "Prioritize books": "Priorytetyzuj książki",
    "No books match your search": "Nie znaleziono książek",
    "No books yet. Click + to add one!": "Brak książek. Kliknij + aby dodać!",
    "0 books": "0 książek",

    // ── Table column headers ──
    "Title": "Tytuł",
    "Type": "Typ",
    "Status": "Status",
    "Pages": "Strony",
    "Author": "Autor",
    "Rating": "Ocena",
    "Genre": "Gatunek",

    // ── Type labels (plural, for type distribution) ──
    "Books": "Książki",
    "Articles": "Artykuły",
    "Newspapers": "Gazety",
    "Magazines": "Czasopisma",
    "Comics": "Komiksy",
    "Mangas": "Mangi",
    "Theses": "Prace naukowe",
    "Workbooks": "Ćwiczenia",
    "Others": "Inne",

    // ── Type labels (singular, for badges) ──
    "Book": "Książka",
    "Article": "Artykuł",
    "Newspaper": "Gazeta",
    "Magazine": "Czasopismo",
    "Comic": "Komiks",
    "Manga": "Manga",
    "Thesis": "Praca naukowa",
    "Workbook": "Ćwiczenia",
    "Other": "Inne",

    // ── BookForm ──
    "Add New Book": "Dodaj nową książkę",
    "Edit Book": "Edytuj książkę",
    "Title *": "Tytuł *",
    "Author *": "Autor *",
    "Type:": "Typ:",
    "Technical book / Textbook": "Książka techniczna / Podręcznik",
    "Priority": "Priorytet",
    "Set Priority": "Ustaw priorytet",
    "Remove Priority": "Usuń priorytet",
    "Standard": "Standardowa",
    "Audiobook": "Audiobook",
    "Audiobook Support": "Wsparcie audiobookiem",
    "Bad": "Słaba",
    "Weak": "Kiepska",
    "Average": "Przeciętna",
    "Good": "Dobra",
    "Very good": "Bardzo dobra",
    "Excellent": "Wybitna",
    "Not rated": "Bez oceny",
    "DETAILS": "SZCZEGÓŁY",
    "Language": "Język",
    "Series": "Seria",
    "Series name...": "Nazwa serii...",
    "Published Year": "Rok wydania",
    "Current page": "Aktualna strona",
    "ISBN": "ISBN",
    "Publisher": "Wydawca",
    "Publisher name": "Nazwa wydawcy",
    "Select genre...": "Wybierz gatunek...",
    "Search or add genre...": "Szukaj lub dodaj gatunek...",
    "READING DATES": "DATY CZYTANIA",
    "Started": "Rozpoczęto",
    "Finished": "Zakończono",
    "Set today": "Ustaw dziś",
    "NOTES": "NOTATKI",
    "Your thoughts about the book...": "Twoje przemyślenia o książce...",
    "Title is required": "Tytuł jest wymagany",
    "Author is required": "Autor jest wymagany",
    "Add Book": "Dodaj książkę",
    "Save": "Zapisz",
    "Add Cover": "Dodaj okładkę",
    "Change": "Zmień",
    "Select Cover Image": "Wybierz okładkę",

    // ── BookDetails ──
    "Back": "Wróć",
    "Edit": "Edytuj",
    "Delete": "Usuń",
    "Series: ": "Seria: ",
    "Non-fiction": "Literatura faktu",
    "pages": "stron",
    "Progress": "Postęp",
    "MY REVIEW": "MOJA RECENZJA",
    "Write your review...": "Napisz swoją recenzję...",
    "Save Review": "Zapisz recenzję",
    "FAVORITE QUOTES": "ULUBIONE CYTATY",
    "+ Add Quote": "+ Dodaj cytat",
    "No quotes yet": "Brak cytatów",
    "HIGHLIGHTS": "WAŻNE FRAGMENTY",
    "+ Add Highlight": "+ Dodaj fragment",
    "No highlights yet": "Brak fragmentów",
    "SUMMARY": "PODSUMOWANIE",
    "(empty)": "(puste)",
    "Collapse": "Zwiń",
    "Expand": "Rozwiń",
    "Write a brief summary of the book...": "Napisz krótkie podsumowanie książki...",
    "Save Summary": "Zapisz podsumowanie",
    "Delete Book": "Usuń książkę",
    "Are you sure you want to delete": "Czy na pewno chcesz usunąć",
    "Add Quote": "Dodaj cytat",
    "Quote text": "Tekst cytatu",
    "Enter quote...": "Wpisz cytat...",
    "Page:": "Strona:",
    "(0 = no page)": "(0 = brak strony)",
    "Add": "Dodaj",
    "Add Highlight": "Dodaj fragment",
    "Highlight name...": "Nazwa fragmentu...",
    "Note": "Notatka",
    "Important info...": "Ważne informacje...",

    // ── StatisticsView ──
    "Total Books": "Wszystkie książki",
    "Books Read": "Przeczytane",
    "Pages Read": "Przeczytane strony",
    "Avg Pages/Book": "Śr. stron/książkę",
    "Avg Completion": "Śr. ukończenie",
    "Library Composition": "Skład biblioteki",
    "No books in library yet": "Brak książek w bibliotece",
    "Average Rating": "Średnia ocena",
    "Top Genre": "Najczęstszy gatunek",
    "books": "książek",
    "Read Rate": "Wskaźnik przeczytania",
    "of": "z",
    "Monthly Books Read": "Miesięczna liczba przeczytanych",
    "No monthly data yet": "Brak danych miesięcznych",
    "Yearly Reading Stats": "Roczne statystyki czytania",
    "Year": "Rok",
    "Total Pages": "Łączne strony",
    "Avg Pages": "Śr. strony",
    "Avg Rating": "Śr. ocena",
    "No yearly data yet": "Brak danych rocznych",
    "Genre Distribution": "Rozkład gatunków",
    "No genre data yet": "Brak danych o gatunkach",
    "Bars": "Słupki",
    "Pie": "Kołowy",
    "Treemap": "Treemap",

    // ── StatisticsView: tabs ──
    "Overview": "Przegląd",
    "Sessions": "Sesje",

    // ── StatisticsSessions ──
    "Current streak": "Aktualna seria",
    "Longest streak": "Najdłuższa seria",
    "Pages read": "Przeczytane strony",
    "Pages per reading day": "Stron na dzień czytania",
    "Pages per day": "Strony dziennie",
    "By weekday": "Wg dnia tygodnia",
    "Recent sessions": "Ostatnie sesje",
    "No reading sessions yet": "Brak sesji czytania",
    "Sessions are recorded when you add pages": "Sesje są zapisywane, gdy dodajesz strony",
    "All tags": "Wszystkie tagi",
    "Challenge type": "Typ wyzwania",
    "Books read": "Przeczytane książki",
    "Number of pages": "Liczba stron",
    "Target pages per day": "Cel stron dziennie",
    "Timeframe": "Okres",
    "Period": "Przedział",
    "End date": "Data końcowa",
    "years": "lata",
    "To go:": "Zostało:",
    "target": "cel",
    "now": "teraz",
    "left": "zostało",
    "Series": "Serie",
    "series": "serii",
    "No series yet": "Brak serii",
    "Undo": "Cofnij",
    "Deleted": "Usunięto",
    "Book restored": "Książka przywrócona",
    "Export MD": "Eksport MD",
    "Export notes (Markdown)": "Eksport notatek (Markdown)",
    "Exported notes for": "Wyeksportowano notatki dla",
    "Reading activity": "Aktywność czytania",
    "Less": "Mniej",
    "More": "Więcej",
    "Completion projection": "Prognoza ukończenia",
    "pages left": "stron zostało",
    "in": "za",
    "pg/day": "str./dzień",
    "Not enough data to estimate": "Za mało danych do prognozy",
    "Edit session": "Edytuj sesję",
    "Date": "Data",
    "A session for that day already exists": "Sesja na ten dzień już istnieje",
    "Failed to update session": "Nie udało się zaktualizować sesji",
    "Invalid session values": "Nieprawidłowe wartości sesji",
    "Setting pages to 0 deletes this session": "Ustawienie 0 stron usuwa tę sesję",

    // ── ChallengesView ──
    "Completed": "Ukończone",
    "Expired": "Wygasłe",
    "Due:": "Termin:",
    "Elapsed:": "Upłynęło:",
    "Remaining:": "Pozostało:",
    "< 1 day": "< 1 dzień",
    "1 day": "1 dzień",
    "days": "dni",
    "1 month": "1 miesiąc",
    "months": "miesięcy",
    "expired": "wygasłe",
    "Avg pages/day to finish:": "Śr. stron/dzień do ukończenia:",
    "done!": "ukończone!",
    "pages/day": "stron/dzień",
    "Hide books": "Ukryj książki",
    "Show books": "Pokaż książki",
    "No challenges yet. Click + to create one!": "Brak wyzwań. Kliknij + aby utworzyć!",
    "New Challenge": "Nowe wyzwanie",
    "Challenge name": "Nazwa wyzwania",
    "e.g. Summer Reading": "np. Letnie czytanie",
    "Number of books": "Liczba książek",
    "Duration (months)": "Czas trwania (miesiące)",
    "month": "miesiąc",
    "Deadline:": "Termin:",
    "Create": "Utwórz",

    // ── Context menu ──
    "Start Reading": "Rozpocznij czytanie",
    "Add Pages": "Dodaj strony",
    "Mark as Read": "Oznacz jako przeczytane",
    "Update Progress": "Aktualizuj postęp",
    "Review": "Recenzja",

    // ── Year filter ──
    "All time": "Wszystkie lata",

    // ── Sorting ──
    "Default": "Domyślne",
    "Newest": "Najnowsze",
    "Oldest": "Najstarsze",

    // ── Menu bar ──
    "About BookWorm": "O BookWorm",
    "Check for Updates...": "Sprawdź aktualizacje...",
    "File": "Plik",
    "View": "Widok",
    "Languages": "Języki",
    "Theme": "Motyw",
    "Help": "Pomoc",

    // ── About dialog ──
    "Version": "Wersja",
    "All rights reserved.": "Wszystkie prawa zastrzeżone."
};

function translate(key, lang) {
    if (lang === "pl" && _pl[key] !== undefined)
        return _pl[key];
    return key;
}

// Plural helper for type distribution
function typePlural(typeKey, lang) {
    if (typeKey === "thesis") {
        return lang === "pl" ? "Prace naukowe" : "Theses";
    }
    var label = typeKey.charAt(0).toUpperCase() + typeKey.slice(1) + "s";
    if (lang === "pl" && _pl[label] !== undefined)
        return _pl[label];
    return label;
}

// Capitalize and translate singular type
function typeLabel(typeKey, lang) {
    var label = typeKey.charAt(0).toUpperCase() + typeKey.slice(1);
    if (lang === "pl" && _pl[label] !== undefined)
        return _pl[label];
    return label;
}

// Month labels
function monthLabels(lang) {
    if (lang === "pl")
        return ["Sty","Lut","Mar","Kwi","Maj","Cze","Lip","Sie","Wrz","Paź","Lis","Gru"];
    return ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
}

// Weekday labels, Monday-first (index 0 = Monday ... 6 = Sunday)
function dayLabels(lang) {
    if (lang === "pl")
        return ["Pon","Wt","Śr","Czw","Pt","Sob","Nd"];
    return ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
}
