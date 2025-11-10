# MySQL-Projects
Contains exported MySQL databases for Paymo and TataLoan
# MySQL Projects

This repository contains exported MySQL databases.

## Databases
- **Paymo.sql** — Payment tracking system database
- **TataLoan.sql** — Loan management database

## How to Import in MySQL Workbench
1. Go to **Server → Data Import**
2. Choose **Import from Self-Contained File**
3. Select the `.sql` file
4. Click **Start Import**

Or using command line:
```bash
mysql -u root -p < Paymo.sql
mysql -u root -p < TataLoan.sql
