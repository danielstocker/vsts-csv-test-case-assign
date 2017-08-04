# VSTS | CSV Test Case Assign 
## This script uses a csv file to assign existing VSTS test cases to a defined set of plans and suites
### Any suites or plans that do not exist, will be created. 

**Expected CSV...**

see the example file in this repo
* Column1: Plan Name
* Column2: Suites Names (supports several suites in a tree structure)
* Column3: IDs of existing test cases (supports lists)

**What the script does...**

* Read in the CSV

* Step through the plans
  * make sure every plan is only checked once
  * check if it exists already
    * if not, create it
    * https://www.visualstudio.com/en-us/docs/integrate/api/test/plans

* Step through each line
  * run a recursive query to make sure the suite tree structure exists
  * if the requested tree or parts of it do not exist, create the relevant suite(s)
    * https://www.visualstudio.com/en-us/docs/integrate/api/test/suites
  * create an array of test cases (delimiter: "/")
  * check what test cases are assigned to the suite already
    * assign those that are missing
    * https://www.visualstudio.com/en-us/docs/integrate/api/test/casesit

**More Info**

You need a Personal Access Token to access the VSTS API. 
On premises (against TFS) you can use a PAT as well, but Integrated auth is also an option. You may need to adjust the script slightly for TFS on-premises, as you may not be targeting the "DefaultCollection". 

This script was created for PowerShell 5 and later. (previous versions may work)

Related blog post: http://www.danielstocker.net/test-manager-in-vsts-creating-suites-and-linking-test-cases-from-a-csv-template/ 
