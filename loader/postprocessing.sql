-- Contents of this file are executed as SQL commands after the Koha-migration is complete
--DELETE b FROM borrowers b WHERE b.borrowernumber NOT IN (SELECT borrowernumber FROM issues i WHERE b.borrowernumber=i.borrowernumber) AND b.borrowernumber NOT IN (SELECT borrowernumber FROM reserves r WHERE b.borrowernumber = r.borrowernumber);
--

UPDATE additional_contents SET borrowernumber=NULL WHERE borrowernumber NOT IN (SELECT borrowernumber FROM borrowers);

SELECT 'postprocessing steps done';
