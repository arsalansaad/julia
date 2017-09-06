# This file is a part of Julia. License is MIT: https://julialang.org/license

import Base.LibGit2: AbstractCredentials, UserPasswordCredentials, SSHCredentials,
    CachedCredentials, CredentialPayload, Payload

"""
Emulates the LibGit2 credential loop to allows testing of the credential_callback function
without having to authenticate against a real server.
"""
function credential_loop(
        valid_credential::AbstractCredentials,
        url::AbstractString,
        user::Option{<:AbstractString},
        allowed_types::UInt32,
        payload::CredentialPayload)
    cb = Base.LibGit2.credentials_cb()
    libgitcred_ptr_ptr = Ref{Ptr{Void}}(C_NULL)
    payload_ptr = Ref(payload)

    # Number of times credentials were authenticated against. With the real LibGit2
    # credential loop this would be how many times we sent credentials to the remote.
    num_authentications = 0

    # Emulate how LibGit2 uses the credential callback by repeatedly calling the function
    # until we find valid credentials or an exception is raised.
    err = Cint(0)
    while err == 0
        err = ccall(cb, Cint, (Ptr{Ptr{Void}}, Cstring, Cstring, Cuint, Ptr{Void}),
            libgitcred_ptr_ptr, url, unwrap(user, C_NULL), allowed_types, pointer_from_objref(payload_ptr))
        num_authentications += 1

        # Check if the callback provided us with valid credentials
        if !isnull(payload.credential) && unwrap(payload.credential) == valid_credential
            break
        end

        if num_authentications > 50
            error("Credential callback seems to be caught in an infinite loop")
        end
    end

    # Note: LibGit2.GitError(0) will not work if an error message has been set.
    git_error = if err == 0
        LibGit2.GitError(LibGit2.Error.None, LibGit2.Error.GIT_OK, "No errors")
    else
        LibGit2.GitError(err)
    end

    return git_error, num_authentications
end

function credential_loop(
        valid_credential::UserPasswordCredentials,
        url::AbstractString,
        user::Option{<:AbstractString}=null,
        payload::CredentialPayload=CredentialPayload())
    credential_loop(valid_credential, url, user, 0x000001, payload)
end

function credential_loop(
        valid_credential::SSHCredentials,
        url::AbstractString,
        user::Option{<:AbstractString}=null,
        payload::CredentialPayload=CredentialPayload();
        use_ssh_agent::Bool=false)

    if !use_ssh_agent
        if isnull(payload.cache)
            payload.cache = Some(CachedCredentials())
        end
        cache = unwrap(payload.cache)

        m = match(LibGit2.URL_REGEX, url)
        default_cred = LibGit2.reset!(SSHCredentials(true), -1)
        default_cred.usesshagent = "N"
        LibGit2.get_creds!(cache, "ssh://$(m[:host])", default_cred)
    end

    credential_loop(valid_credential, url, user, 0x000046, payload)
end

function credential_loop(
        valid_credential::UserPasswordCredentials,
        url::AbstractString,
        user::AbstractString,
        payload::CredentialPayload=CredentialPayload())
    credential_loop(valid_credential, url, Some(user), payload)
end

function credential_loop(
        valid_credential::SSHCredentials,
        url::AbstractString,
        user::AbstractString,
        payload::CredentialPayload=CredentialPayload();
        use_ssh_agent::Bool=false)
    credential_loop(valid_credential, url, Some(user), payload, use_ssh_agent=use_ssh_agent)
end
