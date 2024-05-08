function Sync-QualysTagAssignment {
    <#
        .SYNOPSIS
            Synchronize tags from an external source of truth to Qualys.
        .DESCRIPTION
            This function synchronizes tags from an external source of truth to Qualys.
        .EXAMPLE
        .NOTES
            Authors:
            - Carter Kindley
            - Jack Nemitz

    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (

        [Parameter(ValueFromPipeline, Mandatory = $true)]
        [QualysAsset]
        $InputAsset,

        [pscredential]
        $InputCredential = $Credential,

        [string]
        $InputQualysApiUrl = $QualysApiUrl,

        [hashtable]
        $CategoryDefinitions

    )

    begin {
        # Pull all unique qualys tags from pipelined InputAssets into a hashtable of id and QualysTag object
        $tags = @{}

        $InputAsset | ForEach-Object {
            $_.tags.list.TagSimple | ForEach-Object {
                if (-not $tags.ContainsKey($_.id)) {
                    $tags.Add($_.id, $(Get-QualysTag -TagId $_.id -InputCredential $InputCredential -InputQualysApiUrl $InputQualysApiUrl -RetrieveParentTag))
                }
            }
        }
        $responses = @{
            Removed  = New-Object 'System.Collections.ArrayList'
            Added    = New-Object 'System.Collections.ArrayList'
            Existing = New-Object 'System.Collections.ArrayList'
            Issues   = New-Object 'System.Collections.ArrayList'
        }
    }

    process {

        # Downselect assetTags from $tags to only those that are in the InputAsset's tags.list.TagSimple array
        # [hashtable](QualysTagID:QualysTag)
        $assetTags = @{}
        $InputAsset.tags.list.TagSimple | ForEach-Object {
            $tagID = $_.id
            $assetTags.Add($tagID, $($tags.GetEnumerator() | Where-Object { $_.Key -eq $tagID }).Value)
        }
        # Loop through each external vtag and compare to Qualys tags
        $InputAsset.vtags | ForEach-Object {
            $vtag = $_
            $QualysTag = $($tags.GetEnumerator() | Where-Object { $_.Value.name -eq "$($InputAsset.prefix)$($vtag.name)" }).Value
            if ($null -eq $QualysTag) {
                $QualysTag = Get-QualysTag -TagName "$($InputAsset.prefix)$($vtag.name)" -InputCredential $InputCredential -InputQualysApiUrl $InputQualysApiUrl
                if ($null -eq $QualysTag) {
                    $responses.Issues.Add("$vtag could not be found in Qualys.")
                    continue
                }
                $tags.Add($QualysTag.id, $QualysTag)
            }
        }

        #loop over unique Category property values of vtags
        $InputAsset.vtags | Select-Object -ExpandProperty Category -Unique | ForEach-Object {
            # Check to see if any CategoryDefinitions are missing from the vTags categories
            if (-not $CategoryDefinitions.ContainsKey($_)) {
                $responses.Issues.Add("Category $_ is not defined in the CategoryDefinitions.")
            }
            $category = $_.name
            # may need slightly more sophisticated matching
            [QualysTag[]]$tagsOfCategory = $assetTags.Values | Where-Object {$_.parentTag.name -match $category}
            if ($tagsOfCategory.Count -eq 0) {
                # tag of category $category does not exist on InputAsset
            } elseif ($tagsOfCategory.Count -gt 1) {
                # more than one tag of category $category exists on InputAsset
            } else {
                # there exists exactly one tag of category $category on InputAsset
            }
        }

    }

    end {
        return $responses
    }

}
