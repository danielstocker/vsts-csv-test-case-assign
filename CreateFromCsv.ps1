$personalAccessToken = "pat"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "",$personalAccessToken)))
$accountname = "acc"

# WHAT DOES THIS SCRIPT DO?
# 1) it will load in a CSV with a collection of test plans, suites, and case ids
# 2) it will check if each plan name exists, if a plan name does not exists, a test plan with that name will be created
# 3) it will check if each suite within the plan exists, if one or more do not exist, the process will create the suites
# 3.1) the script supports suites within suites. Use "/" in your suite names to create multi-layer suites
# 4) it will make sure each test ID listed under a suite name is linked in that suite
# 4.1) the script will never delete test links (this has to be done with the user's consent through the UI)
# 4.2) the script only works with existing test cases
# 4.3) all suites need to have unique names at their folder level as the script only differentiates by name (not by ID)
# 4.4) each line can contain one or more test case IDs. Use "/" in the test case ID field to add more than one at once

# read companion CSV
$csvContent = Import-Csv ".\testCreate.csv"

# seclect project in account
$project = "proj"

## START OF REUSABLE FUNCTIONS
function Make-SuiteTreeStructure($Root, $Collection) {
    
    $output = @()

    $thisNode = $Root.name
    $output += $thisNode
    $children = @()

    foreach($suite in $Collection) {
        if($suite.parent -eq $null) {
            continue;
        }
        if($suite.parent.url.ToString().EndsWith("/" + ($Root.Id.ToString()))) {
            $children += Make-SuiteTreeStructure -Root $suite -Collection $Collection
        }
    }

    foreach($child in $children) {
        $output += $thisNode + "/" + $child
    }

    return $output

}

function Make-SuiteIdStructure($Root, $Collection) {
    
    $output = @{}

    $thisNode = $Root.name
    $output += @{ $thisNode = $Root.Id }
    $children = @{}

    foreach($suite in $Collection) {
        if($suite.parent -eq $null) {
            continue;
        }
        if($suite.parent.url.ToString().EndsWith("/" + ($Root.Id.ToString()))) {
            $children += Make-SuiteIdStructure -Root $suite -Collection $Collection
        }
    }

    foreach($child in $children.Keys) {
        $key = ($thisNode + "/" + $child)
        $output += @{$key = $children[$child]}
    }

    return $output

}
## END OF REUSABLE FUNCTIONS

# check if all test plans exists, create any that do not
# https://www.visualstudio.com/en-us/docs/integrate/api/test/plans
$call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans?api-version=1.0"
$result = Invoke-RestMethod -Uri $call -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

$requestedPlans = $csvContent.'Plan Name'
$prunedPlanNames = @()

# get unique names
foreach($plan in $requestedPlans) {
    if(!$prunedPlanNames.Contains($plan)) {
        $prunedPlanNames += $plan
    }
}

# check if any of the requested plans exists
$existingAndRequestedPlans = @()
foreach($existingPlan in $result.value) {
    if($prunedPlanNames.Contains($existingPlan.name)) {
        Write-Host $existingPlan.name "already exits. No need to create it..."
        $existingAndRequestedPlans += $existingPlan.name
    }
}

# create plans that do not exist
foreach($planName in $prunedPlanNames) {
    if($existingAndRequestedPlans.Contains($planName)) {
        continue
    }

    $call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans?api-version=1.0"
    $body = '{
        "name": "' + $planName +'"
    }'
    $result = Invoke-RestMethod -Uri $call -Method Post -Body $body -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

    Write-Host $planName "has been created..."
}

# get up to date list of plans
# https://www.visualstudio.com/en-us/docs/integrate/api/test/plans
$call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans?api-version=1.0"
$result = Invoke-RestMethod -Uri $call -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
$plans = $result.value

# create suites in each plan at the right level
foreach($element in $csvContent) {
    # identify plan id
    $planId = (-1)
    $planName = $null

    foreach($plan in $plans) {
        if($plan.name.Equals($element.'Plan Name')) {
            $planId = $plan.id
            $planName = $plan.name
        }
    }

    if($planId -lt 0) {
        throw("Could not find ID for plan with name " + $plan.name + ". It is likely that it does not exist or that your network request was blocked/closed.")
    }

    # query current suites and children
    # https://www.visualstudio.com/en-us/docs/integrate/api/test/suites
    $call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans/" + $planId + "/suites?$asTreeView=true&api-version=2.0-preview"
    $result = Invoke-RestMethod -Uri $call -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
    $suitesAndChildren = @{}
    $existingSuitesAndIds = @{}
    
    # strucutre suites and children in tree structure
    foreach($suite in $result.value) {
        if($suite.parent -eq $null) {
            # found root
            $suitesAndChildren = Make-SuiteTreeStructure -Root $suite -Collection $result.value
            $existingSuitesAndIds += Make-SuiteIdStructure -Root $suite -Collection $result.value

        }

        
    }

    $suiteName = $element.'Test Suite Name'
    
    while($suiteName.EndsWith("/")) {
        $suiteName.Substring(0,$suiteName.Length - 1)
    }

    $requestedPath = ($planName + "/" + $suiteName).Split("/")

    # create teach suite
    for($level = 0; $level -lt $requestedPath.Length; $level++) {
        $exists = $false
        $searchString = ""
        for($a = 0; $a -lt ($level+1); $a++) {
            $searchString += $requestedPath[$a] 
            if($a -lt ($level)) {
                $searchString += "/"
            }
        }

        if($suitesAndChildren.Contains($searchString)) {
            $exists = $true
        }

        if($exists -eq $false) {
           $searchStringSplit = $searchString.Split("/")
           $parentIndex = $existingSuitesAndIds[$planName]

           if($searchString.Contains("/")) {
               $parentIndex = $existingSuitesAndIds[$searchString.Substring(0, $searchString.LastIndexOf("/"))]
           }

           $call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans/" + $planId + "/suites/" + $parentIndex + "?api-version=1.0"
           $body = '{
               "name": "' + $requestedPath[$level] + '",
               "suiteType": "StaticTestSuite"
           }'
           
           Write-Host "Creating test suite" $searchString "..."
           $result = Invoke-RestMethod -Uri $call -Method Post -Body $body -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
           $existingSuitesAndIds += @{$searchString = $result.value.id.ToString()}
        }
    }

    # add test case(s) to suites
    $requestedPath = ($planName + "/" + $suiteName).Split("/")

    for($a = 0; $a -lt $requestPath.count; $a++) {
        $searchString += $requestedPath[$a] 
        if($a -lt ($requestPath.count)) {
            $searchString += "/"
        }
    }

    $testcasestring = $element.'Test Case ID'

    $testCaseArray = @()
    if($testcasestring.Contains("/")) {
        $testCaseArray = $testcasestring.Split("/")
    } else {
        $testCaseArray += $testcasestring
    }
    $prunedTestCaseArray = @()

    # making sure we do not add any tests twice (this leads to an error message)
    $call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans/" + $planId + "/suites/" + $existingSuitesAndIds[$searchString] + "/testcases?api-version=1.0"
    $result = Invoke-RestMethod -Uri $call -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
    foreach($test in $testCaseArray) {
        $contained = $false
        foreach($testCase in $result.value) {
            if($testCase.testCase.id.ToSTring().Equals($test)) {
                $contained = $true
            }
        }

        if($contained -eq $false) {
            $prunedTestCaseArray += $test
        }
    }
        

    # actually adding the test(s)
    if($prunedTestCaseArray.Count -lt 1) {
        Write-Host "No changes need to be made to" $searchString "; test(s):" $testcasestring "is/are already in this particular suite"
        continue
    }

    if($prunedTestCaseArray.Count -gt 1) {
        $testcasestring = ($prunedTestCaseArray -join ",")
    } else {
        $testcasestring = $prunedTestCaseArray
    }

    Write-Host "Adding test case(s)" $testcasestring "to" $searchString
    $call = "https://" + $accountname + ".visualstudio.com/DefaultCollection/" + $project + "/_apis/test/plans/" + $planId + "/suites/" + $existingSuitesAndIds[$searchString] + "/testcases/" + $testcasestring + "?api-version=1.0"
    $result = Invoke-RestMethod -Uri $call -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
}
