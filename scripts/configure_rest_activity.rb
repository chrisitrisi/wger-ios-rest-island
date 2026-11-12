# Adds the native ActivityKit target without regenerating Flutter's Xcode project.
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
group = project.main_group.find_subpath('RestActivity', true)
group.set_source_tree('<group>')
group.set_path('RestActivity')
def source(group, name)
  group.files.find { |f| f.path == name } || group.new_file(name)
end
attributes = source(group, 'RestAttributes.swift')
plugin = source(group, 'RestActivityPlugin.swift')
# The Live Activity buttons: the widget draws them, the app runs them
island_intent = source(group, 'WorkoutIslandIntent.swift')
runner.add_file_references([attributes, plugin, island_intent, source(group, 'WorkoutShortcuts.swift')])
widget = project.targets.find { |t| t.name == 'WgerRestWidget' } ||
  project.new_target(:app_extension, 'WgerRestWidget', :ios, '16.2')
widget.add_file_references([attributes, island_intent, source(group, 'RestWidget.swift')])
runner.add_dependency(widget)
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } ||
  runner.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
# Embed before Flutter's scripts: Thin Binary reads the finished app bundle.
runner.build_phases.delete(embed)
runner.build_phases.insert(0, embed)
unless embed.files_references.include?(widget.product_reference)
  embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
runner.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'at.chrisitrisi.wger.rest'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Sideload.entitlements'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
end
widget.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'at.chrisitrisi.wger.rest.widget',
    'PRODUCT_NAME' => 'WgerRestWidget',
    'PRODUCT_MODULE_NAME' => 'WgerRestWidget',
    'INFOPLIST_FILE' => 'RestActivity/Info.plist',
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '16.2',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'FLUTTER_BUILD_NAME' => '2.1.2',
    'FLUTTER_BUILD_NUMBER' => '290',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'DEVELOPMENT_TEAM' => '',
  })
end
project.save
