# Ham Radio Lookup

Ham Radio Lookup is a macOS app for searching United States amateur radio licenses. It reads either a MySQL database or a SQLite file built from the FCC Universal Licensing System amateur file and the RadioID DMR user list. Searches run on your Mac. The app does not send a query to a server.

The window is titled **Ham Radio Lookup**. The Xcode project and the app bundle are named `HamRadioQuery` (`com.dstokes.HamRadioQuery`).

## What you can look up

Each result is one license record:

| Column | Meaning |
| --- | --- |
| Call Sign | The station call sign |
| First Name, Last Name, Street Address, City, State, ZIP | The licensee's name and mailing address |
| Operator Class | Amateur Extra, Advanced, General, Technician, Technician Plus, or Novice |
| License Status | Active, Canceled, Expired, Terminated, Term Pending, Pending Legal Status, or Parent Station Canceled |
| FRN | The FCC Registration Number |
| Region Code | The FCC region stored with the amateur record |
| DMR ID | The RadioID DMR ID for that call sign, or a dash when RadioID has none |

Operator class and license status are stored as the FCC's single-letter codes and shown as the full names above. A status other than Active is drawn in a secondary color.

## Requirements

- macOS 15 or later
- An internet connection the first time you create the database, and again whenever you update it
- Xcode, if you are building the app yourself
- MySQL or MariaDB, only if you choose MySQL instead of the built-in SQLite file

The license file is about 190 MB. Building the database also downloads the RadioID user list and can take several minutes.

## Choose MySQL or SQLite

Search uses one database at a time. Open **Settings** (Ham Radio Lookup > Settings) or click **Database** in the toolbar. At the top of that window, **Database** is a pair of radio buttons: **SQLite** and **MySQL**. The choice is saved, and the next search uses it.

**SQLite** is the default. The license data lives in a file on this Mac, so no database server is required. The settings window shows the file path and the last time it was built. **Create Database…** or **Update Database…** downloads the FCC and RadioID files and builds that file. Search stays disabled until the file exists.

**MySQL** reads and updates a MySQL or MariaDB server. Choosing it shows the connection fields:

| Field | Local default |
| --- | --- |
| Host | `127.0.0.1` |
| Port | `3306` |
| Database | `fcc` |
| Username | `fccuser` |
| Password | `fccuser` |

**Use Local Defaults** fills in those values. They match the local database used by the FCC web app in the sibling `fcc` project. Change them if your server is elsewhere or uses a different account.

**Test Connection** tries the host, port, database, username, and password currently on screen. It does not save them. A successful test says which database it reached. A failure names the connection problem, such as a server that is not running, a rejected password, or a database name that does not exist.

**Save** stores the host, port, database name, and username in the app's preferences. The password is stored in the Keychain. Until you save, a successful test applies only to that test. Searches use the saved connection.

**Update Database…** downloads the FCC and RadioID files and rebuilds the license tables in the saved MySQL database. The database is created if that account is allowed to create it. This step needs the `mysql` command-line client, such as the one installed with Homebrew MariaDB. Search itself does not need that client. If the server is not running, the search says it could not connect.

## Create or update the database

The app does not include license data.

With **SQLite** selected, the first launch says the database has not been created, and **Search** stays disabled until one exists. Create it from the main window, from **Tools > Create License Database…**, or from **Create Database…** in Settings. The finished file is installed only after the import succeeds, so a failed update leaves the previous file in place. If the file is more than 8 days old, the app asks you to update it, and search still works.

With **MySQL** selected, save the connection first, then use **Update Database…** in Settings or **Tools > Update License Database…**. That rebuilds the license tables in the MySQL database named in Settings. Search stays available while you do this.

Either choice downloads the same files:

1. `l_amat.zip` from the FCC (`https://data.fcc.gov/download/pub/uls/complete/l_amat.zip`)
2. The license files inside that archive
3. `user.csv` from RadioID (`https://radioid.net/static/user.csv`)

You can cancel while a download is in progress. Import cannot be cancelled. Downloaded files stay in `/tmp/ham-radio-lookup` until the next restart. The next create or update removes that folder and downloads fresh copies.

## Search

Enter at least one of call sign, first name, last name, city, or state, then click **Search** or press Return.

- **Call sign** matches the whole call sign. Typing is uppercased. `w7dns` finds `W7DNS` and does not find other call signs that merely contain those letters.
- **First name**, **last name**, and **city** match from the start. `Em` matches Emmett. A name or city must begin with what you typed.
- **State** matches the two-letter abbreviation exactly. `id` is treated as `ID`.
- `%` and `_` in a name or city are ordinary characters, not wildcards.

**Clear** resets the fields, the options, and the results.

If every field is blank, Search asks you to enter a call sign, name, city, or state.

### Options

**Options** is collapsed until you open it.

**License Status** defaults to Active only. Turn on other statuses to include them. If none are selected, every status matches.

**Operator Class** defaults to all classes. If none are selected, every class matches.

**Apply Title Case** capitalizes names, street addresses, and cities in the results. Call signs, state, ZIP, FRN, region, and DMR ID are unchanged. Turn it off to see the FCC's original capitalization.

## Results

Results are ordered by last name, then first name. Click a column header to sort by that column instead.

**Filter results** narrows the rows already on screen. It matches any visible column, and it also matches the one-letter operator class and license status codes as well as their full names. Command-F moves the cursor to that field. The status line shows how many rows are visible. This filter does not search the database again.

Select rows and use the context menu, or:

| Action | Menu | Shortcut |
| --- | --- | --- |
| Copy the selected rows as tab-separated text, with a header | Edit > Copy Selected Rows | Command-Shift-C |
| Export the rows currently shown as CSV | File > Export Results…, or the Export toolbar button | Command-Shift-E |
| Look up one row's call sign | Double-click the row, or choose Search This Call Sign | |

Copy and export use the full operator class and license status names. The suggested CSV name is `Ham Radio Lookup`. Export includes the filtered rows, so a filter changes what is written.

Double-clicking a row, or choosing **Search This Call Sign**, puts that call sign in the search field, clears the name, city, and state, and searches again. That action applies to one row.

## Where files are stored

| File | Location |
| --- | --- |
| SQLite license database | `~/Library/Application Support/Ham Radio Query/licenses.sqlite` |
| MySQL password | Keychain item for `com.dstokes.HamRadioQuery` |
| FCC and RadioID downloads | `/tmp/ham-radio-lookup` |

The SQLite folder is created when the first SQLite import succeeds. Deleting `licenses.sqlite` makes the app treat that file as missing. The age check uses the import time stored inside the file, not the file's modification date. The MySQL database stays on the server you configured.

## Build and run

Open `HamRadioQuery.xcodeproj` and run the **HamRadioQuery** scheme.

A Release build from the command line:

```sh
xcodebuild \
  -project HamRadioQuery.xcodeproj \
  -scheme HamRadioQuery \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CONFIGURATION_BUILD_DIR="$PWD/build/Release" \
  build
```

The app is written to `build/Release/HamRadioQuery.app`. The `build` directory is gitignored.

Quit any running copy before opening that app. macOS will keep using the copy that is already running because both use the bundle ID `com.dstokes.HamRadioQuery`.

Unit tests:

```sh
xcodebuild \
  -project HamRadioQuery.xcodeproj \
  -scheme HamRadioQuery \
  -destination 'platform=macOS' \
  test
```

The tests build a small temporary SQLite file. They do not download the FCC archive and they do not write the Application Support database.
