#!/usr/bin/python

import re
import csv
from glob import glob
from collections import defaultdict

zipcode = '23111'
matches = []

for csvFile in glob('23111.csv'):
    f = open(csvFile, 'r')
    reader = csv.reader(f, delimiter=',')
    sums = defaultdict(int)

    for row in reader:
        if len(row): # Deal with blank lines
           try:
              name  = row[9]
              spent = row[2].strip("()")
              address = row[23]
              zipc  = row[25]

              if zipc == zipcode:
                  try:
                     sums[name] += float(spent)
                  except IndexError:
                     pass
                  except ValueError:
                     continue
                  if [name,address,zipc] not in matches:
                      matches.append([name,address,zipc])
           except IndexError:
              pass

for n,a,z in matches:
    print "%s ($%s), %s %s" % (str(n), sums[n], str(a), str(z))
