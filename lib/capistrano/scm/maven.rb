require "capistrano/scm/plugin"
require "uri"
require 'net/http'

class Capistrano::SCM::Maven < Capistrano::SCM::Plugin
  def set_defaults; end

  def define_tasks
    eval_rakefile File.expand_path("../tasks/maven.rake", __FILE__)
  end

  def register_hooks
    after "deploy:new_release_path", "maven:create_release"
    before "deploy:check", "maven:check"
    before "deploy:set_current_revision", "maven:set_current_revision"
  end

  def fetch_revision
    fetch(:maven_artifact_version)
  end

  def mkdirs
    backend.execute :mkdir, "-p", repo_path
    backend.execute :mkdir, "-p", release_path
  end

  def check_repo_is_reachable
    return reachable?(repo_url)
  end

  def check_artifact_is_available
    return reachable?(artifact_url)
  end

  def archive_needs_refresh?
    snapshot = fetch(:maven_artifact_version).include? 'SNAPSHOT'
    snapshot || backend.test(" [ ! -f #{local_filename} ] ")
  end

  def download
    backend.info "Downloading artifact from #{artifact_url}"
    if archive_needs_refresh?
      backend.execute :curl, '--fail', '--silent', '-o', local_filename, artifact_url
    end
  end

  def release
    backend.execute :tar, '-xzf', local_filename, '-C', release_path
  end

  private

  def repo_url
    "#{fetch(:maven_endpoint)}/#{fetch(:maven_repository)}/"
  end

  # ex. http://artifactory.library.wisc.edu:8081/artifactory/libs-snapshot/edu/wisc/library/sdg/alma-invoice-to-wisdm-check-request/0.0.1-SNAPSHOT/alma-invoice-to-wisdm-check-request-0.0.1-SNAPSHOT-cap.tar.gz
  def artifact_url
    [
      fetch(:maven_endpoint),
      fetch(:maven_repository),
      *fetch(:maven_group_id).split('.'),
      fetch(:maven_artifact_name),
      fetch(:maven_artifact_version),
      remote_filename
    ].join('/')
  end

  def remote_filename
    "#{fetch(:maven_artifact_name)}-#{fetch(:maven_artifact_version)}-#{fetch(:maven_artifact_style, 'bin')}.#{fetch(:maven_artifact_ext)}"
  end

  def local_filename
    "#{repo_path.to_s}/#{fetch(:maven_artifact_version)}.#{fetch(:maven_artifact_ext)}"
  end

  def reachable?(uri_str, limit = 3)
    raise ArgumentError, 'too many HTTP redirects' if limit == 0

    backend.info "Checking #{uri_str} for reachability.."
    uri = URI(uri_str)
    response = Net::HTTP.new(uri.host, uri.port).request_head(uri.path)

    case response
    when Net::HTTPSuccess then
      backend.info "#{uri_str} is reachable"
      true
    when Net::HTTPRedirection then
      location = response['location']
      warn "redirected to #{location}"
      reachable?(location, limit - 1)
    else
      false
    end
  end
end