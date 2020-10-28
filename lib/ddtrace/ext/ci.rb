require 'ddtrace/ext/git'

module Datadog
  module Ext
    # Defines constants for CI tags
    # rubocop:disable Metrics/ModuleLength:
    module CI
      TAG_JOB_URL = 'ci.job.url'.freeze
      TAG_PIPELINE_ID = 'ci.pipeline.id'.freeze
      TAG_PIPELINE_NAME = 'ci.pipeline.name'.freeze
      TAG_PIPELINE_NUMBER = 'ci.pipeline.number'.freeze
      TAG_PIPELINE_URL = 'ci.pipeline.url'.freeze
      TAG_PROVIDER_NAME = 'ci.provider.name'.freeze
      TAG_WORKSPACE_PATH = 'ci.workspace_path'.freeze

      PROVIDERS = [
        ['APPVEYOR'.freeze, :extract_appveyor],
        ['TF_BUILD'.freeze, :extract_azure_pipelines],
        ['BITBUCKET_COMMIT'.freeze, :extract_bitbucket],
        ['BUILDKITE'.freeze, :extract_buildkite],
        ['CIRCLECI'.freeze, :extract_circle_ci],
        ['GITHUB_SHA'.freeze, :extract_github_actions],
        ['GITLAB_CI'.freeze, :extract_gitlab],
        ['JENKINS_URL'.freeze, :extract_jenkins],
        ['TEAMCITY_VERSION'.freeze, :extract_teamcity],
        ['TRAVIS'.freeze, :extract_travis]
      ].freeze

      module_function

      def tags(env)
        provider = PROVIDERS.find { |c| env.key? c[0] }
        return {} if provider.nil?
        normalize_branch = %r{^refs/(heads/)?}
        normalize_origin = %r{^origin/}
        normalize_tag = %r{^tags/}
        tags = send(provider[1], env).reject { |_, v| v.nil? }
        unless tags[Git::TAG_TAG].nil?
          tags[Git::TAG_TAG] = tags[Git::TAG_TAG].gsub(normalize_branch, '').gsub(normalize_origin, '').gsub(normalize_tag, '')
          tags.delete Git::TAG_BRANCH
        end
        tags[Git::TAG_BRANCH] = tags[Git::TAG_BRANCH].gsub(normalize_branch, '').gsub(normalize_origin, '').gsub(normalize_tag, '') if tags.key? Git::TAG_BRANCH
        tags[Git::TAG_DEPRECATED_COMMIT_SHA] = tags[Git::TAG_COMMIT_SHA] if tags.key? Git::TAG_COMMIT_SHA

        # Expand ~
        workspace_path = tags[TAG_WORKSPACE_PATH]
        if !workspace_path.nil? && (workspace_path == '~' || workspace_path.start_with?('~/'))
          tags[TAG_WORKSPACE_PATH] = File.expand_path(workspace_path)
        end
        tags
      end

      # CI providers

      def extract_appveyor(env)
        url = "https://ci.appveyor.com/project/#{env['APPVEYOR_REPO_NAME']}/builds/#{env['APPVEYOR_BUILD_ID']}"
        {
          TAG_PROVIDER_NAME => 'appveyor',
          Git::TAG_REPOSITORY_URL =>  "https://github.com/#{env['APPVEYOR_REPO_NAME']}.git",
          Git::TAG_COMMIT_SHA => env['APPVEYOR_REPO_COMMIT'],
          TAG_WORKSPACE_PATH => env['APPVEYOR_BUILD_FOLDER'],
          TAG_PIPELINE_ID => env['APPVEYOR_BUILD_ID'],
          TAG_PIPELINE_NAME => env['APPVEYOR_REPO_NAME'],
          TAG_PIPELINE_NUMBER => env['APPVEYOR_BUILD_NUMBER'],
          TAG_PIPELINE_URL => url,
          TAG_JOB_URL => url,
          Git::TAG_BRANCH => (env['APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH'] || env['APPVEYOR_REPO_BRANCH']),
          Git::TAG_TAG => env['APPVEYOR_REPO_TAG_NAME']
        }
      end

      def extract_azure_pipelines(env)
        if env['SYSTEM_TEAMFOUNDATIONSERVERURI'] && env['SYSTEM_TEAMPROJECT'] && env['BUILD_BUILDID']
          base_url = "#{env['SYSTEM_TEAMFOUNDATIONSERVERURI']}#{env['SYSTEM_TEAMPROJECT']}" \
            "/_build/results?buildId=#{env['BUILD_BUILDID']}"
          pipeline_url = base_url + '&_a=summary'
          job_url = base_url + "&view=logs&j=#{env['SYSTEM_JOBID']}&t=#{env['SYSTEM_TASKINSTANCEID']}"
        else
          pipeline_url = job_url = nil
        end
        branch_or_tag = (
          env['SYSTEM_PULLREQUEST_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCH'] || env['BUILD_SOURCEBRANCHNAME']
        )
        if branch_or_tag.include? 'tags/'
          branch = nil
          tag = branch_or_tag
        else
          branch = branch_or_tag
          tag = nil
        end
        {
          TAG_PROVIDER_NAME => 'azurepipelines',
          TAG_WORKSPACE_PATH => env['BUILD_SOURCESDIRECTORY'],
          TAG_PIPELINE_ID => env['BUILD_BUILDID'],
          TAG_PIPELINE_NAME => env['BUILD_DEFINITIONNAME'],
          TAG_PIPELINE_NUMBER => env['BUILD_BUILDID'],
          TAG_PIPELINE_URL => pipeline_url,
          TAG_JOB_URL => job_url,
          Git::TAG_REPOSITORY_URL => (env['SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI'] || env['BUILD_REPOSITORY_URI']),
          Git::TAG_COMMIT_SHA => (env['SYSTEM_PULLREQUEST_SOURCECOMMITID'] || env['BUILD_SOURCEVERSION']),
          Git::TAG_BRANCH => branch,
          Git::TAG_TAG => tag
        }
      end

      def extract_bitbucket(env)
        url = "https://bitbucket.org/#{env['BITBUCKET_REPO_FULL_NAME']}/addon/pipelines/home#" \
          "!/results/#{env['BITBUCKET_BUILD_NUMBER']}"
        {
          Git::TAG_BRANCH => env['BITBUCKET_BRANCH'],
          Git::TAG_COMMIT_SHA => env['BITBUCKET_COMMIT'],
          Git::TAG_REPOSITORY_URL => env['BITBUCKET_GIT_SSH_ORIGIN'],
          Git::TAG_TAG => env['BITBUCKET_TAG'],
          TAG_JOB_URL => url,
          TAG_PIPELINE_ID => env['BITBUCKET_PIPELINE_UUID'] ? env['BITBUCKET_PIPELINE_UUID'].tr('{}', '') : None,
          TAG_PIPELINE_NAME => env['BITBUCKET_REPO_FULL_NAME'],
          TAG_PIPELINE_NUMBER => env['BITBUCKET_BUILD_NUMBER'],
          TAG_PIPELINE_URL => url,
          TAG_PROVIDER_NAME => 'bitbucket',
          TAG_WORKSPACE_PATH => env['BITBUCKET_CLONE_DIR']
        }
      end

      def extract_buildkite(env)
        {
          TAG_PROVIDER_NAME => 'buildkite',
          Git::TAG_REPOSITORY_URL => env['BUILDKITE_REPO'],
          Git::TAG_COMMIT_SHA => env['BUILDKITE_COMMIT'],
          TAG_WORKSPACE_PATH => env['BUILDKITE_BUILD_CHECKOUT_PATH'],
          TAG_PIPELINE_ID => env['BUILDKITE_BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['BUILDKITE_BUILD_NUMBER'],
          TAG_PIPELINE_URL => env['BUILDKITE_BUILD_URL'],
          Git::TAG_BRANCH => env['BUILDKITE_BRANCH']
        }
      end

      def extract_circle_ci(env)
        {
          TAG_PROVIDER_NAME => 'circleci',
          Git::TAG_REPOSITORY_URL => env['CIRCLE_REPOSITORY_URL'],
          Git::TAG_COMMIT_SHA => env['CIRCLE_SHA1'],
          TAG_WORKSPACE_PATH => env['CIRCLE_WORKING_DIRECTORY'],
          TAG_PIPELINE_NUMBER => env['CIRCLE_BUILD_NUM'],
          TAG_PIPELINE_URL => env['CIRCLE_BUILD_URL'],
          Git::TAG_BRANCH => env['CIRCLE_BRANCH']
        }
      end

      def extract_github_actions(env)
        {
          TAG_PROVIDER_NAME => 'github',
          Git::TAG_REPOSITORY_URL => env['GITHUB_REPOSITORY'],
          Git::TAG_COMMIT_SHA => env['GITHUB_SHA'],
          TAG_WORKSPACE_PATH => env['GITHUB_WORKSPACE'],
          TAG_PIPELINE_ID => env['GITHUB_RUN_ID'],
          TAG_PIPELINE_NUMBER => env['GITHUB_RUN_NUMBER'],
          TAG_PIPELINE_URL => "#{env['GITHUB_REPOSITORY']}/commit/#{env['GITHUB_SHA']}/checks",
          Git::TAG_BRANCH => env['GITHUB_REF']
        }
      end

      def extract_gitlab(env)
        {
          TAG_PROVIDER_NAME => 'gitlab',
          Git::TAG_REPOSITORY_URL => env['CI_REPOSITORY_URL'],
          Git::TAG_COMMIT_SHA => env['CI_COMMIT_SHA'],
          TAG_WORKSPACE_PATH => env['CI_PROJECT_DIR'],
          TAG_PIPELINE_ID => env['CI_PIPELINE_ID'],
          TAG_PIPELINE_NUMBER => env['CI_PIPELINE_IID'],
          TAG_PIPELINE_URL => env['CI_PIPELINE_URL'],
          TAG_JOB_URL => env['CI_JOB_URL'],
          Git::TAG_BRANCH => (env['CI_COMMIT_BRANCH'] || env['CI_COMMIT_REF_NAME'])
        }
      end

      def extract_jenkins(env)
        {
          TAG_PROVIDER_NAME => 'jenkins',
          Git::TAG_REPOSITORY_URL => env['GIT_URL'],
          Git::TAG_COMMIT_SHA => env['GIT_COMMIT'],
          TAG_WORKSPACE_PATH => env['WORKSPACE'],
          TAG_PIPELINE_ID => env['BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['BUILD_NUMBER'],
          TAG_PIPELINE_URL => env['BUILD_URL'],
          TAG_JOB_URL => env['JOB_URL'],
          Git::TAG_BRANCH => env['GIT_BRANCH']
        }
      end

      def extract_teamcity(env)
        {
          TAG_PROVIDER_NAME => 'teamcity',
          Git::TAG_REPOSITORY_URL => env['BUILD_VCS_URL'],
          Git::TAG_COMMIT_SHA => env['BUILD_VCS_NUMBER'],
          TAG_WORKSPACE_PATH => env['BUILD_CHECKOUTDIR'],
          TAG_PIPELINE_ID => env['BUILD_ID'],
          TAG_PIPELINE_NUMBER => env['BUILD_NUMBER'],
          TAG_PIPELINE_URL => (
            env['SERVER_URL'] && env['BUILD_ID'] ? "#{env['SERVER_URL']}/viewLog.html?buildId=#{env['SERVER_URL']}" : nil
          )
        }
      end

      def extract_travis(env)
        {
          Git::TAG_BRANCH => (env['TRAVIS_PULL_REQUEST_BRANCH'] || env['TRAVIS_BRANCH']),
          Git::TAG_COMMIT_SHA => env['TRAVIS_COMMIT'],
          Git::TAG_REPOSITORY_URL =>  "https://github.com/#{env['TRAVIS_REPO_SLUG']}.git",
          Git::TAG_TAG => env['TRAVIS_TAG'],
          TAG_JOB_URL => env['TRAVIS_JOB_WEB_URL'],
          TAG_PIPELINE_ID => env['TRAVIS_BUILD_ID'],
          TAG_PIPELINE_NAME => env['TRAVIS_REPO_SLUG'],
          TAG_PIPELINE_NUMBER => env['TRAVIS_BUILD_NUMBER'],
          TAG_PIPELINE_URL => env['TRAVIS_BUILD_WEB_URL'],
          TAG_PROVIDER_NAME => 'travisci',
          TAG_WORKSPACE_PATH => env['TRAVIS_BUILD_DIR']
        }
      end
    end
  end
end
