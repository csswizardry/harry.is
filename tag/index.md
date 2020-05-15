---
title: "All Tags"
layout: default
---

<h1>{{ page.title }}</h1>

<nav class="c-tag-list">
{% for tag in site.tags %}
  <a href="/{{ tag[0] }}/" class="c-tag">{{ tag[0] }}</a>
{% endfor %}
</nav>
