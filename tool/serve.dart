import 'dart:async';
import 'dart:io';

import 'package:angular/src/source_gen/source_gen.dart';
import 'package:angular/src/transform/stylesheet_compiler/transformer.dart';
import 'package:angular_compiler/angular_compiler.dart';
import 'package:build/build.dart';
import 'package:build_barback/build_barback.dart';

import 'package:build_compilers/build_compilers.dart';

import 'package:build_runner/build_runner.dart';
import 'package:build_test/builder.dart';
import 'package:sass_builder/sass_builder.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future main() async {
  var graph = new PackageGraph.forThisPackage();
  var buildActions = <BuildAction>[];
  buildActions.addAll(_sassBuildActions(graph));
  buildActions.addAll(_angularBuildActions(graph));
  buildActions.add(new BuildAction(new TestBootstrapBuilder(), graph.root.name,
      inputs: ['test/**_test.dart']));

  void addBuilderForAll(Builder builder, String inputExtension) {
    for (var packageNode in graph.orderedPackages) {
      buildActions
          .add(new BuildAction(builder, packageNode.name, isOptional: true));
    }
  }

  addBuilderForAll(new ModuleBuilder(), '.dart');
  addBuilderForAll(new UnlinkedSummaryBuilder(), moduleExtension);
  addBuilderForAll(new LinkedSummaryBuilder(), moduleExtension);
  addBuilderForAll(new DevCompilerBuilder(), moduleExtension);

  buildActions.add(new BuildAction(
      new DevCompilerBootstrapBuilder(), graph.root.name,
      inputs: ['web/**.dart', 'test/**.browser_test.dart']));

  var serveHandler = await watch(
    buildActions,
    deleteFilesByDefault: true,
    writeToCache: true,
  );

  var server =
      await shelf_io.serve(serveHandler.handlerFor('web'), 'localhost', 8080);
  var testServer =
      await shelf_io.serve(serveHandler.handlerFor('test'), 'localhost', 8081);

  await serveHandler.currentBuild;
  stderr.writeln('Serving `web` at http://localhost:8080/');
  stderr.writeln('Serving `test` at http://localhost:8081/');

  await serveHandler.buildResults.drain();
  await server.close();
  await testServer.close();
}

List<BuildAction> _angularBuildActions(PackageGraph graph) {
  var actions = <BuildAction>[];
  var flags = new CompilerFlags(genDebugInfo: false);
  var builders = [
    const TemplatePlaceholderBuilder(),
    createSourceGenTemplateCompiler(flags),
    new StylesheetCompiler(flags),
  ];
  var packages = ['angular']
    ..addAll(graph.dependentsOf('angular').map((n) => n.name));
  for (var builder in builders) {
    for (var package in packages) {
      actions.add(new BuildAction(builder, package));
    }
  }
  return actions;
}

List<BuildAction> _sassBuildActions(PackageGraph graph) {
  var actions = <BuildAction>[];
  for (var package in graph.dependentsOf('sass_builder')) {
    var outputExtension =
        package.name == 'angular_components' ? '.scss.css' : '.css';
    actions.add(new BuildAction(
        new SassBuilder(outputExtension: outputExtension), package.name,
        inputs: ['**.scss']));
  }
  return actions;
}
