#!/usr/bin/env node
/*
2025-03-14 from https://gist.github.com/pabloasanchez/1a2fa03eb7e72544e532957402c2ae52

Usage: ./to-netscape-bookmarks.sh urls_file | tee bookmarks.html
  urls_file is a simple textfile with urls separated by breakline

Prereqs: `brew install pup`
*/

const { exec } = require('child_process'), fs = require('fs'), readline = require('readline')

const file = process.argv[2]
if(!file) return console.log('Usage: to-netscape-bookmarks input.txt')

const HEADER = '<!DOCTYPE NETSCAPE-Bookmark-file-1><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8"><Title>Bookmarks</Title><H1>Bookmarks</H1><DL><p>'
FOOTER = '</DL><p>',
LINK = (s, title, url) => `<DT><A HREF="${url}">${title}</A>`

async function init() {
  console.log(HEADER)

  const data = fs.readFileSync(file, 'utf-8')
  const d = data.split(/\r?\n/)

  for await (const line of d) {
    if(line) {
      let title = await getTitle(line)
      title = title.split('\n')[0]
      console.log(LINK`${title} ${line}`)
      await wait(1000) // Throttle to prevent too many requests
    }
  }

  console.log(FOOTER)
}

function run(command='echo') {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) return reject(error)
      if (stderr) return reject(error)
      return resolve(stdout)
    })
  })
}

async function getTitle(url) {
  return await run(`curl -sL "${url}" | pup 'title text{}'`)
}

async function wait(ms) {
  return new Promise( resolve => setTimeout(resolve, ms))
}

(async function() { await init() })()
