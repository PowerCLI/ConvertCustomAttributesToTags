function ConvertCustomAttributesToTags{
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory = $True, Position = 1)]
      [VMware.VimAutomation.ViCore.Types.V1.VIServer]$Server
   )
   
   Write-Host "Collecting information about custom attributes..."
   
   # Collect all custom attributes
   $customAttributeList = Get-CustomAttribute -Server $server
   # We will store information about the tag categories we need to create
   $tagCategoryInfo = @{}
   # We will store the newly created categories here for faster access later
   # on in the script (rather than retrieving them each time from the server)
   $tagCategories = @()
   
   # Collect information about what tag categories need to be created
   # (We need to know what are the supported entity types for each category)
   foreach ($customAttribute in $customAttributeList) {
      # The $tagCategoryInfo is a hashtable, where the key is the category name
      # and the value is a list of the applicable entity types
      if (-not $tagCategoryInfo.Contains($customAttribute.Name)) {
         $tagCategoryInfo[$customAttribute.Name] = @()
      }
      
      $targetType = $customAttribute.TargetType
      
      # If no target type is specified for the custom attribute - it means
      # that it applies to all entities.
      if ($targetType -eq $null) {
         $targetType = "All"
      }
      
      $tagCategoryInfo[$customAttribute.Name] += $targetType
   }
   
   Write-Host "Collecting information about existing tags and tag categories..."
   
   # Collect any existing tag categories and tags. We will need to reuse those so that
   # there is no collision when creating the new ones.
   $existingCategories = Get-TagCategory -Server $server | select -ExpandProperty Name
   $existingTags = Get-Tag -Server $server | foreach {$_.ToString()}
   
   Write-Host "Creating the necessary tag categories..."
   
   # Create the tag categories based on the collected $tagCategoryInfo.
   # We will store the newly created categories in $tagCategories
   # variable and use it later on in the script.
   foreach ($tagCategoryName in $tagCategoryInfo.Keys) {
      # If such a category already exists - just update its EntityType
      # to include all types that it needs to support.
      if ($existingCategories -contains $tagCategoryName) {
         $tagCategories += `
            Set-TagCategory `
               -Category $tagCategoryName `
               -AddEntityType $tagCategoryInfo[$tagCategoryName] `
               -Server $server
      } else {
      # The category doesn't exist so we need to create it
         $tagCategories += `
            New-TagCategory `
               -Name $tagCategoryName `
               -EntityType $tagCategoryInfo[$tagCategoryName] `
               -Cardinality Single `
               -Server $server
      }
   }
   
   Write-Host "Collecting information about the inventory items and their annotations..."
   
   # Collect information about all annotations values (so that
   # we can create a tag for each one and then tag the entities
   # with them)
   $annotationInfo = @{}
   # Custom attributes/annotations are only supported for
   # inventory objects. Collect all inventory objects and then
   # see what annotations they have.
   $inventoryItemList = Get-Inventory -Server $server
   
   # Go throuhg each inventory item and check what annotations
   # it has. Record this information in $annotationInfo so that
   # we can then create the necessary tags and assign them to
   # the corresponding inventory items.
   foreach ($inventoryItem in $inventoryItemList) {
      $annotationList = Get-Annotation -Entity $inventoryItem
      
      foreach ($annotation in $annotationList) {
         # The keys in $annotationInfo represent the tag categories
         # and the values are a hashtable with the tag information.
         if (-not $annotationInfo.Contains($annotation.Name)) {
            $annotationInfo[$annotation.Name] = @{}
         }
         
         # For each tag we keep information about what inventory items
         # are tagged with it. E.g. $annotationInfo[$annotation.Name][$annotation.Value]
         # is a list of the inventory items.
         if (($annotation.Value -ne $null) -and ($annotation.Value -ne "")) {
            if (-not $annotationInfo[$annotation.Name].Contains($annotation.Value)) {
               $annotationInfo[$annotation.Name][$annotation.Value] = @()
            }
            
            $annotationInfo[$annotation.Name][$annotation.Value] += $inventoryItem
         }
      }
   }
   
   Write-Host "Creating the necessary tags..."
   
   # Create the tags in each category
   foreach ($categoryName in $annotationInfo.Keys) {
      # Find the tag category object from the $tagCategories list.
      # This way we don't have to make a server call for each category.
      $category = $tagCategories | where {$_.Name -eq $categoryName}
      
      foreach ($tagName in $annotationInfo[$categoryName].Keys) {
         $tagFullName = "{0}/{1}" -f $categoryName, $tagName
         
         # If the tag doesn't exist - create it
         if (-not ($existingTags -contains $tagFullName)) {
            New-Tag `
               -Name $tagName `
               -Category $category `
            | Out-Null
         }
      }
   }
   
   Write-Host "Assigning the tags to the inventory items..."
   
   # Tag each object as appropriate. To do that we go through each
   # category and through each tag in that category - and see what
   # objects are tagged with them.
   foreach ($categoryName in $annotationInfo.Keys) {
      $category = $tagCategories | where {$_.Name -eq $categoryName}
      
      # Go through each tag in the category
      foreach ($tagName in $annotationInfo[$categoryName].Keys) {
         $tag = Get-Tag -Name $tagName -Category $category
         
         # Go through each inventory item that had the annotation value
         # set to them and assign the corresponding tag.
         foreach ($inventoryItem in $annotationInfo[$categoryName][$tagName]) {
            New-TagAssignment `
               -Tag $tag `
               -Entity $inventoryItem `
            | Out-Null
         }
      }
   }
   
   Write-Host "Done"
}