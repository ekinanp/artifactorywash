#!/usr/bin/env ruby
# encoding: UTF-8

require 'artifactory'
require 'wash'
require 'json'
require 'uri'

JFROG_CONF = File.join(Dir.home, ".jfrog", "jfrog-cli.conf")

# TODO: Once https://github.com/puppetlabs/wash-ruby/issues/34 is fixed,
# :mtime and :path declarations should move over to Artifact. Metadata
# schema declarations should move over to the Entry class.

def configure_client
  config = JSON.parse(File.read(JFROG_CONF))
  # TODO: Update plugin to work w/ multiple artifactory instances?
  instance_config = config['artifactory'][0]
  unless instance_config
    # TODO: Add instructions for initializing jfrog config
    raise "no artifactory instance specified. Try running "
  end
  Artifactory.configure do |config|
    config.endpoint = instance_config['url']
    config.username = instance_config['user']
    config.password = instance_config['password']
    config.api_key = instance_config['apiKey']
    # TODO: Include SSL config?
  end
rescue StandardError => error
  raise "Error reading #{JFROG_CONF}: #{error}"
end

def uri_escape(value)
  URI.escape(value)
end

# Pass this in so that 'find' will still fetch an entry's full metadata
METADATA_SCHEMA = { "type": "object" }

# Entry class is necessary so we can initialize the client in allocate.
# Otherwise each implemented method would need to call 'configure_client'
# before doing anything else.
#
# TODO: If this becomes a common pattern, could be worth adding a helper
# to wash-ruby that runs some initialization code during entry re-construction
class Entry < Wash::Entry
  class << self
    def allocate
      configure_client
      super
    end
  end
end

# Class name should be Artifactory but this would conflict
# with the artifactory gem
class ArtifactoryRoot < Entry
  label 'artifactory'
  is_singleton
  parent_of 'RepositoryType'
  metadata_schema METADATA_SCHEMA
  description <<~DESC
    A plugin for managing artifactory. It parses credentials from Jfrog's config file,
    which is typically located at ~/.jfrog/jfrog-cli.conf.

    The artifactory plugin organizes your repositories by their repository type. Currently
    only 'local', 'remote' and 'virtual' are supported. The plugin lets you view and delete
    artifacts (and repositories), and filter them using 'find' on things like their mtime
    (last modified time) or on an artifact's item properties.
  DESC

  def init(_config)
    # We don't need to do any initialization, so do nothing here
  end

  def list
    ['local', 'remote', 'virtual'].map do |type|
      RepositoryType.new(type)
    end
  end
end

class RepositoryType < Entry
  label 'repository_type'
  parent_of 'Repository'
  metadata_schema METADATA_SCHEMA

  def initialize(type)
    @name = type
  end

  def list
    Artifactory.client.get('/api/repositories', params = { type: @name }).map do |repo_json|
      Repository.new(repo_json)
    end
  end
end

# Common helpers used by the Repository and FolderArtifact classes
def list_folder(path)
  Artifactory.client.get("api/storage/#{path}?list&listFolders=1&mdTimestamps=1")['files'].map do |file|
    if file["folder"]
      FolderArtifact.new(path, file)
    else
      FileArtifact.new(path, file)
    end
  end
end

def storage_info(path)
  # For some reason, we need separate requests to api/storage in order to
  # get the storage info + item properties
  url = "api/storage/#{path}"
  storage_json = Artifactory.client.get(url)
  storage_json.delete("children")
  begin
    properties_json = Artifactory.client.get("#{url}?properties")
    storage_json.merge!(properties_json)
  rescue Artifactory::Error::HTTPError => e
    unless e.code == 404 && e.message =~ /properties.*found/
      raise e
    end
    # Item doesn't have any properties so just pass-thru
  end
  storage_json
end

class Repository < Entry
  label 'repository'
  parent_of 'FolderArtifact', 'FileArtifact'
  metadata_schema METADATA_SCHEMA
  description <<~DESC
    This is a repository.
  DESC

  def initialize(repo_json)
    @name = repo_json['key']
    @partial_metadata = repo_json
  end

  def metadata
    escaped_name = uri_escape(@name)
    metadata_json = storage_info(escaped_name)
    metadata_json['config'] = Artifactory.client.get("api/repositories/#{escaped_name}")
    metadata_json
  end

  def delete
    Artifactory.client.delete("api/repositories/#{uri_escape(@name)}")
    true
  end

  def list
    list_folder("#{uri_escape(@name)}/")
  end
end

class Artifact < Entry
  def initialize(parent, json)
    @mtime = json["lastModified"]
    @partial_metadata = json
    # json['uri'] starts with a "/" so this concatenation's
    # OK.
    @path = "#{parent.chomp('/')}#{uri_escape(json['uri'])}"
    # Eliminate the leading "/"
    @name = json['uri'][1..-1]
  end

  def delete
    Artifactory.client.delete(@path)
    true
  end

  def metadata
    storage_info(@path)
  end
end

class FolderArtifact < Artifact
  label 'folder'
  parent_of 'FolderArtifact', 'FileArtifact'
  metadata_schema METADATA_SCHEMA
  attributes :mtime
  state :path

  def initialize(parent, folder_json)
    super(parent, folder_json)
  end

  def list
    list_folder(@path)
  end
end

class FileArtifact < Artifact
  label 'file'
  metadata_schema METADATA_SCHEMA
  attributes :mtime, :size
  state :path

  def initialize(parent, file_json)
    super(parent, file_json)
    @size = file_json['size']
  end

  def read
    content = ''
    Artifactory.client.get(@path) do |chunk|
      content << chunk
    end
    content
  end
end

Wash.enable_entry_schemas
Wash.prefetch_entry_schemas
Wash.pretty_print
Wash.run(ArtifactoryRoot, ARGV)
