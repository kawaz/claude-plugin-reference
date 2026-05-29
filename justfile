# claude-plugin-reference push
# (push-guard hook 経由でこの task を使うことで、直叩き block を回避)

push: ensure-clean
    jj bookmark set main -r @-
    jj git push --bookmark main --allow-new
    claude plugin marketplace update claude-plugin-reference
    claude plugin update claude-plugin-reference@claude-plugin-reference

# uncommitted change がある状態で push しない
ensure-clean:
    @if [ "$(jj log -r @ --no-graph -T 'empty')" = "false" ]; then echo "ERROR: @ has uncommitted changes" >&2; exit 1; fi

# version bump (patch / minor / major)
bump-version bump="patch": ensure-clean
    new_version=$(bump-semver {{ bump }} .claude-plugin/plugin.json .claude-plugin/marketplace.json --write --no-hint) && jj commit -m "Release v${new_version}"

# validate
validate:
    claude plugin validate .
