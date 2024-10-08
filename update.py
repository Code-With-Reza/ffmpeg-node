#!/usr/bin/env python3


import json
import os
import shutil
from urllib import request

FFMPEG_RELEASES = "https://endoflife.date/api/ffmpeg.json"

DIR_FORMAT_STR = "docker-images/{0}/{1}"
IMAGE_FORMAT_STR = "{0}/Dockerfile".format(DIR_FORMAT_STR)
TEMPLATE_STR = "templates/Dockerfile-template.{0}"

# https://ffmpeg.org/olddownload.html
# https://endoflife.date/ffmpeg

with request.urlopen(FFMPEG_RELEASES) as conn:
    ffmpeg_releases = conn.read().decode("utf-8")
keep_version = []

# When building locally ( and trying to keep the docker-images folder clean'ish )
# it might be useful to skip some of the older versions
# skip_ffmpeg_cycle = ["7.0.2", "6.1", "5.1", "4.4", "4.3", "4.2", "3.4", "2.8"]
skip_ffmpeg_cycle = []
for v in json.loads(ffmpeg_releases):
    if not v["eol"] and not v["cycle"] in skip_ffmpeg_cycle:
        if "0.0" in v["latest"]:
            v["latest"] = v["latest"].replace("0.0", "0")
        keep_version.append(v["latest"])

VARIANTS = [
    {"name": "ubuntu2404", "parent": "ubuntu"},
    {"name": "ubuntu2204", "parent": "ubuntu"},
    {"name": "alpine313", "parent": "alpine"},
    {"name": "scratch313", "parent": "scratch"},
    {"name": "vaapi2204", "parent": "vaapi"},
    {"name": "nvidia2204", "parent": "nvidia"},
]


all_parents = sorted(set([sub["parent"] for sub in VARIANTS]))
gitlabci = ["stages:\n  - lint\n"]
azure = []

for parent in all_parents:
    gitlabci.append(f"  - {parent}\n")


SKIP_VARIANTS = {
    "2.8": ["alpine313", "nvidia2004", "vaapi2004", "scratch313", "ubuntu2404"],
    "3.4": ["ubuntu2404"],
    "4.2": ["alpine313", "ubuntu2404"],
    "4.3": ["alpine313", "scratch313", "ubuntu2404"],
    "4.4": ["ubuntu2404"],
    "5.1": ["scratch313", "ubuntu2404"],
    "6.0": ["alpine313", "nvidia2004", "ubuntu2404"],
    "6.1": ["alpine313", "nvidia2004", "scratch313", "ubuntu2404"],
    "7.0": ["nvidia2004", "vaapi2004", "ubuntu2404"],
    "7.1": ["alpine313", "nvidia2204", "scratch313", "vaapi2204", "ubuntu2204"],
}


def get_shorten_version(version):
    if version == "snapshot":
        return version
    else:
        major, minor, *patch = version.split(".")
        return f"{major}.{minor}"


def get_major_version(version):
    if version == "snapshot":
        return version
    else:
        major, minor, *patch = version.split(".")
        return f"{major}"


print("Preparing docker images for ffmpeg versions: ")

def version_number_greater_than(major, minor, current_version):
    major_number = int(current_version.split(".")[0])
    minor_number = int(current_version.split(".")[1])
    if major_number > major:
        return True
    elif major_number == major and minor_number >= minor:
        return True
    return False

def read_ffmpeg_template_content_based_on_version(current_version, env_or_run="env"):
    """ if the version is 7.1 or later then use the updated ffmpeg templates """
    updated_templates = version_number_greater_than(7, 1, current_version)
    if updated_templates:
        with open(f"templates/Dockerfile-{env_or_run}-ffmpeg-7.1-plus", "r") as tmpfile:
            return tmpfile.read()
    else:
        with open(f"templates/Dockerfile-{env_or_run}", "r") as tmpfile:
            return tmpfile.read()

for version in keep_version:
    print(version)

    ENV_CONTENT = read_ffmpeg_template_content_based_on_version(version, "env")
    RUN_CONTENT = read_ffmpeg_template_content_based_on_version(version, "run")

    skip_variants = None
    for k, v in SKIP_VARIANTS.items():
        if version.startswith(k):
            skip_variants = v
    compatible_variants = [
        v for v in VARIANTS if skip_variants is None or v["name"] not in skip_variants
    ]
    short_version = get_shorten_version(version)
    major_version = get_major_version(version)
    ver_path = os.path.join("docker-images", short_version)
    os.makedirs(ver_path, exist_ok=True)
    for existing_variant in os.listdir(ver_path):
        if existing_variant not in compatible_variants:
            shutil.rmtree(DIR_FORMAT_STR.format(short_version, existing_variant))

    for variant in compatible_variants:
        siblings = [
            v["name"] for v in compatible_variants if v["parent"] == variant["parent"]
        ]
        is_parent = sorted(siblings, reverse=True)[0] == variant["name"]
        dockerfile = IMAGE_FORMAT_STR.format(short_version, variant["name"])
        gitlabci.append(
            f"""
{version}-{variant['name']}:
  extends: .docker
  stage: {variant['parent']}
  variables:
    MAJOR_VERSION: {major_version}
    VERSION: "{short_version}"
    LONG_VERSION: "{version}"
    VARIANT: {variant['name']}
    PARENT: "{variant['parent']}"
    ISPARENT: "{is_parent}"
"""
        )

        azure.append(
            f"""
      {variant["name"]}_{version}:
        MAJOR_VERSION: {major_version}
        VERSION:  {short_version}
        LONG_VERSION: {version}
        VARIANT:  {variant["name"]}
        PARENT: {variant["parent"]}
        ISPARENT:  {is_parent}
"""
        )
        with open(TEMPLATE_STR.format(variant["name"]), "r") as tmpfile:
            template = tmpfile.read()

        FFMPEG_CONFIG_FLAGS = [
            "--disable-debug",
            "--disable-doc",
            "--disable-ffplay",
            "--enable-fontconfig",
            "--enable-gpl",
            "--enable-libass",
            "--enable-libbluray",
            "--enable-libfdk_aac",
            "--enable-libfreetype",
            "--enable-libmp3lame",
            "--enable-libopencore-amrnb",
            "--enable-libopencore-amrwb",
            "--enable-libopus",
            "--enable-libtheora",
            "--enable-libvidstab",
            "--enable-libvorbis",
            "--enable-libvpx",
            "--enable-libwebp",
            "--enable-libx264",
            "--enable-libx265",
            "--enable-libxvid",
            "--enable-libzimg",
            "--enable-libzmq",
            "--enable-nonfree",
            "--enable-openssl",
            "--enable-postproc",
            "--enable-shared",
            "--enable-small",
            "--enable-version3",
            "--extra-libs=-ldl",
            '--prefix="${PREFIX}"',
        ]
        CFLAGS = [
            "-I${PREFIX}/include",
        ]
        LDFLAGS = [
            "-L${PREFIX}/lib",
        ]

        # OpenJpeg 2.1 is not supported in 2.8
        if version[0:3] != "2.8":
            FFMPEG_CONFIG_FLAGS.append("--enable-libopenjpeg")
            FFMPEG_CONFIG_FLAGS.append("--enable-libkvazaar")
        if version == "snapshot" or int(version[0]) > 3:
            FFMPEG_CONFIG_FLAGS.append("--enable-libaom")
            FFMPEG_CONFIG_FLAGS.append("--extra-libs=-lpthread")

        # LibSRT is supported from 4.0
        if version == "snapshot" or int(version[0]) >= 4:
            FFMPEG_CONFIG_FLAGS.append("--enable-libsrt")

        # LibARIBB24 is supported from 4.2
        if version == "snapshot" or float(version[0:3]) >= 4.2:
            FFMPEG_CONFIG_FLAGS.append("--enable-libaribb24")

        if (template.find("meson") > 0) and (
            version == "snapshot" or float(version[0:3]) >= 4.3
        ):
            FFMPEG_CONFIG_FLAGS.append("--enable-libvmaf")

        if (version == "snapshot" or int(version[0]) >= 3) and variant[
            "parent"
        ] == "vaapi":
            FFMPEG_CONFIG_FLAGS.append("--enable-vaapi")

        # libavresample removed on v5, deprecated since v4.0
        # https://github.com/FFmpeg/FFmpeg/commit/c29038f3041a4080342b2e333c1967d136749c0f
        if float(version[0]) < 5:
            FFMPEG_CONFIG_FLAGS.append("--enable-avresample")

        if variant["parent"] == "nvidia":
            CFLAGS.append("-I${PREFIX}/include/ffnvcodec")
            CFLAGS.append("-I/usr/local/cuda/include/")
            LDFLAGS.append("-L/usr/local/cuda/lib64")
            LDFLAGS.append("-L/usr/local/cuda/lib32/")
            FFMPEG_CONFIG_FLAGS.append("--enable-nvenc")
            if version == "snapshot" or int(version[0]) >= 4:
                FFMPEG_CONFIG_FLAGS.append("--enable-cuda")
                FFMPEG_CONFIG_FLAGS.append("--enable-cuvid")
                FFMPEG_CONFIG_FLAGS.append("--enable-libnpp")
        cflags = '--extra-cflags="{0}"'.format(" ".join(CFLAGS))
        ldflags = '--extra-ldflags="{0}"'.format(" ".join(LDFLAGS))
        FFMPEG_CONFIG_FLAGS.append(cflags)
        FFMPEG_CONFIG_FLAGS.append(ldflags)
        FFMPEG_CONFIG_FLAGS.sort()

        COMBINED_CONFIG_FLAGS = " \\\n        ".join(FFMPEG_CONFIG_FLAGS)

        run_content = RUN_CONTENT.replace(
            "%%FFMPEG_CONFIG_FLAGS%%", COMBINED_CONFIG_FLAGS
        )
        env_content = ENV_CONTENT.replace("%%FFMPEG_VERSION%%", version)
        docker_content = template.replace("%%ENV%%", env_content)
        docker_content = docker_content.replace("%%RUN%%", run_content)

        d = os.path.dirname(dockerfile)
        if not os.path.exists(d):
            os.makedirs(d)

        with open(dockerfile, "w") as dfile:
            dfile.write(docker_content)


with open("docker-images/gitlab-ci.yml", "w") as gitlabcifile:
    gitlabcifile.write("".join(gitlabci))

with open("templates/azure.template", "r") as tmpfile:
    template = tmpfile.read()
azure = template.replace("%%VERSIONS%%", "\n".join(azure))


with open("docker-images/azure-jobs.yml", "w") as azurefile:
    azurefile.write(azure)
