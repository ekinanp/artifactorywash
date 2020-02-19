# artifactorywash

A [Wash](https://puppetlabs.github.io/wash/) plugin for managing an artifactory instance. The plugin parses credentials from Jfrog CLI's config file (`~/.jfrog/jfrog-cli.conf`).

```
wash . ❯ stree artifactory
artifactory
└── [repository_type]
    └── [repository]
        ├── [folder]
        │   ├── [folder]
        │   └── [file]
        └── [file]
```

## Installation


1. Clone the repository on your local machine
1. `gem build artifactorywash.gemspec`
1. `gem install artifactorywash`
1. Get the path to the artifactory script with `gem contents artifactorywash`
1. Add to `~/.puppetlabs/wash/wash.yaml`

    ```yaml
    external-plugins:
        - script: '/path/to/artifactorywash/artifactory.rb'
    ```
1. Enjoy!

> If you're a developer, you can use the artifactorywash plugin from source with `bundle install` and set `script: /path/to/artifactorywash/artifactory`.
