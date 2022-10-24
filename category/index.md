---
title: "All Categories"
layout: default
---

<h1 elementtiming="page-title">
  {% include logotype.html %} is writing about

  {% for category in site.categories %}
    {% if forloop.last == true %}
      {% assign separator = '.' %}
    {% else %}
      {% assign separator = ',' %}
    {% endif %}
      <a href="/{{ category[0] }}/" class="c-lozenge">{{ category[0] }}</a>{{ separator }}
  {% endfor %}

</h1>
