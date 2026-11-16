ExUnit.start(
  exclude: if(System.get_env("BEAM_CACHE_IDENTITY_ONLY") == "1", do: [build: true], else: [])
)

defmodule BeamCacheQualification do
  use ExUnit.Case, async: false

  @workflow System.get_env("BEAM_CACHE_WORKFLOW") ||
              Path.expand("../.github/workflows/ci-elixir.yml", __DIR__)

  test "the actual cache identity bootstrap rejects floating versions" do
    workflow = File.read!(@workflow)
    assert workflow =~ "toolchain-cache-mode"

    assert workflow =~
             "version-type: ${{ inputs.toolchain-cache-mode == 'read-write' && 'strict' || 'loose' }}"

    [_, body] =
      Regex.run(
        ~r/name: Identify immutable toolchain cache.*?run: \|\n(.*?)\n      - name:/s,
        workflow
      )

    script =
      body
      |> String.split("\n")
      |> Enum.map_join("\n", &String.replace_prefix(&1, "          ", ""))

    output =
      Path.join(System.tmp_dir!(), "beam-cache-identity-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm(output) end)

    for {otp, elixir, expected} <- [
          {"29.0.2", "1.20.1", 0},
          {"29", "1.20.1", 1},
          {"29.0.2", "~> 1.20", 1}
        ] do
      {_, code} =
        System.cmd("sh", ["-c", script],
          env: [{"OTP_VERSION", otp}, {"ELIXIR_VERSION", elixir}, {"GITHUB_OUTPUT", output}],
          stderr_to_stdout: true
        )

      assert code == expected
    end

    assert File.read!(output) =~ ~r/^identity=[a-f0-9]{64}$/m
    [_, cache] = Regex.run(~r/name: Cache downloaded BEAM tools(.*?)\n      - name:/s, workflow)
    assert cache =~ "runner.tool_cache }}/otp"
    assert cache =~ "runner.tool_cache }}/elixir"
    refute cache =~ "_build"
    refute cache =~ "restore-keys"

    for field <- [
          "runner.os",
          "runner.arch",
          "beam-platform.outputs.identity",
          "inputs.otp-version",
          "inputs.elixir-version",
          "54075bcc5e249e4758d363f27d099f55d843f124"
        ] do
      assert cache =~ field
    end
  end

  @tag build: true, timeout: 300_000
  test "warm and clean compilation agree, and changed source/config/dependency are observed" do
    root =
      Path.join(System.tmp_dir!(), "beam-cache-compile-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(root) end)
    for dir <- ["lib", "config", "fixture_dep/lib"], do: File.mkdir_p!(Path.join(root, dir))

    File.write!(
      Path.join(root, "mix.exs"),
      "defmodule CacheProbe.MixProject do\nuse Mix.Project\ndef project, do: [app: :cache_probe, version: \"0.1.0\", deps: [{:fixture_dep, path: \"fixture_dep\"}]]\ndef application, do: []\nend\n"
    )

    File.write!(
      Path.join(root, "fixture_dep/mix.exs"),
      "defmodule FixtureDep.MixProject do\nuse Mix.Project\ndef project, do: [app: :fixture_dep, version: \"0.1.0\", deps: []]\ndef application, do: []\nend\n"
    )

    source = fn value ->
      File.write!(
        Path.join(root, "lib/cache_probe.ex"),
        "defmodule CacheProbe do\n@configured Application.compile_env(:cache_probe, :value)\ndef value, do: {#{inspect(value)}, @configured, FixtureDep.value()}\nend\n"
      )
    end

    config = fn value ->
      File.write!(
        Path.join(root, "config/config.exs"),
        "import Config\nconfig :cache_probe, value: #{inspect(value)}\n"
      )
    end

    dep = fn value ->
      File.write!(
        Path.join(root, "fixture_dep/lib/fixture_dep.ex"),
        "defmodule FixtureDep do\ndef value, do: #{inspect(value)}\nend\n"
      )
    end

    source.("source-a")
    config.("config-a")
    dep.("dependency-a")

    {_, 0} =
      System.cmd("mix", ["deps.get"],
        cd: root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    run = fn ->
      started = System.monotonic_time(:microsecond)

      {out, code} =
        System.cmd(
          "mix",
          [
            "run",
            "--no-start",
            "-e",
            "IO.puts(\"PROOF:\" <> Base.encode64(:erlang.term_to_binary(CacheProbe.value())))"
          ],
          cd: root,
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      assert code == 0, out
      [_, proof] = Regex.run(~r/PROOF:([^\s]+)/, out)
      value = proof |> Base.decode64!() |> :erlang.binary_to_term([:safe])

      hash =
        root
        |> Path.join("_build/test/lib/cache_probe/ebin/Elixir.CacheProbe.beam")
        |> File.read!()
        |> then(&:crypto.hash(:sha256, &1))

      elapsed = System.monotonic_time(:microsecond) - started
      IO.puts("BUILD_PHASE_US elapsed=#{elapsed} value=#{inspect(value)}")
      {value, hash, elapsed}
    end

    {baseline, hash, cold_us} = run.()
    assert baseline == {"source-a", "config-a", "dependency-a"}
    {^baseline, ^hash, warm_us} = run.()
    File.rm_rf!(Path.join(root, "_build"))
    {^baseline, ^hash, clean_us} = run.()
    source.("source-b-updated")
    {{"source-b-updated", "config-a", "dependency-a"}, changed_hash, _} = run.()
    refute changed_hash == hash
    config.("config-b-updated")
    {{"source-b-updated", "config-b-updated", "dependency-a"}, _, _} = run.()
    dep.("dependency-b-updated")
    {{"source-b-updated", "config-b-updated", "dependency-b-updated"}, _, _} = run.()

    IO.puts(
      "BUILD_TIMINGS_US cold=#{cold_us} warm=#{warm_us} clean=#{clean_us}; default debug/incremental settings; bounded fixture, not application throughput"
    )
  end
end
